# router-apply: commit-confirm style switching for NixOS routers.
# WHY: docs/router-apply-safety.md#automatic-revert-router-apply
#
# INVARIANT: during a trial the new system is activated with
# `switch-to-configuration test`, so the system profile and boot entry still
# point at the previous generation. A crash or reboot before `confirm` comes
# back on the old system; only `confirm` makes the new one the boot default.

STATE_DIR=${ROUTER_APPLY_STATE_DIR:-/run/router-apply}
PROFILE=${ROUTER_APPLY_PROFILE:-/nix/var/nix/profiles/system}
TIMER_UNIT=router-apply-revert
SWITCH_UNIT=router-apply-switch
DEFAULT_TIMEOUT=${ROUTER_APPLY_DEFAULT_TIMEOUT:-300}
SELF=$(readlink -f "$0")

# Units whose rendered configuration `diff` expands, and /etc trees it diffs.
DIFF_UNITS=(nftables keepalived kea-dhcp4-server kea-dhcp6-server kea-dhcp-ddns-server
  systemd-networkd technitium-dns-server frr radvd chronyd)
DIFF_ETC=(systemd/network kea)

usage() {
  cat <<USAGE
Usage: router-apply <command> [args]

  diff <system>                 Show what switching to <system> would change
  switch [--timeout S] <system> Activate <system> for a trial; revert after S
                                seconds (default ${DEFAULT_TIMEOUT}) unless confirmed
  confirm                       Keep the trial system: make it the boot default
  revert                        End the trial now and return to the previous system
  status                        Show the pending trial, if any

<system> is a NixOS system closure (a store path with bin/switch-to-configuration),
for example the output of
  nix build .#nixosConfigurations.<host>.config.system.build.toplevel
copied to the router with nix copy.
USAGE
}

die() { echo "router-apply: $*" >&2; exit 1; }
log() { echo "router-apply: $*" >&2; logger -t router-apply -- "$*" 2>/dev/null || true; }

require_root() { [ "$(id -u)" = 0 ] || die "run as root"; }

check_system() {
  local sys=$1
  [ -n "$sys" ] || die "missing <system>"
  sys=$(readlink -f "$sys")
  [ -x "$sys/bin/switch-to-configuration" ] || die "$sys is not a NixOS system closure"
  printf '%s\n' "$sys"
}

pending() { [ -f "$STATE_DIR/previous" ]; }

# --- diff -------------------------------------------------------------------

store_name() { basename "$1" | cut -d- -f2-; }

# Text files under /nix/store referenced by $1, one level deep.
referenced_files() {
  grep -oE '/nix/store/[a-z0-9]{32}-[^ "'\''`;:)]+' "$1" 2>/dev/null | sort -u | while read -r p; do
    if [ -f "$p" ] && [ "$(stat -c %s "$p")" -lt 524288 ] && grep -Iq . "$p"; then
      printf '%s\n' "$p"
    fi
  done
}

# Unit file plus the configs and scripts it references, two levels deep.
unit_closure() {
  local unit=$1 f
  [ -e "$unit" ] || return 0
  f=$(readlink -f "$unit")
  printf '%s\n' "$f"
  referenced_files "$f" | while read -r p; do
    printf '%s\n' "$p"
    referenced_files "$p"
  done | sort -u
}

diff_unit() {
  local old=$1 new=$2 unit=$3 o n
  o=$old/etc/systemd/system/$unit.service
  n=$new/etc/systemd/system/$unit.service
  [ -e "$o" ] || [ -e "$n" ] || return 0
  if [ ! -e "$o" ]; then echo "--- $unit.service: added"; return 0; fi
  if [ ! -e "$n" ]; then echo "--- $unit.service: removed"; return 0; fi
  [ "$(readlink -f "$o")" = "$(readlink -f "$n")" ] && return 0

  local tmp; tmp=$(mktemp -d)
  unit_closure "$o" > "$tmp/old"
  unit_closure "$n" > "$tmp/new"
  echo "=== $unit.service"
  # Pair files by name without the store hash; show only those that changed.
  while read -r np; do
    local name op
    name=$(store_name "$np")
    op=$(while read -r p; do [ "$(store_name "$p")" = "$name" ] && { echo "$p"; break; }; done < "$tmp/old")
    if [ -z "$op" ]; then
      echo "--- new file: $name"
    elif [ "$op" != "$np" ]; then
      diff -u --label "old/$name" --label "new/$name" "$op" "$np" || true
    fi
  done < "$tmp/new"
  rm -rf "$tmp"
}

cmd_diff() {
  local new old
  new=$(check_system "${1:-}")
  old=$(readlink -f /run/current-system)
  echo "Current: $old"
  echo "New:     $new"
  if [ "$old" = "$new" ]; then echo "No change."; return 0; fi
  echo
  echo "=== Closure (nix store diff-closures)"
  nix --extra-experimental-features nix-command store diff-closures "$old" "$new" || true
  for u in "${DIFF_UNITS[@]}"; do
    diff_unit "$old" "$new" "$u"
  done
  for d in "${DIFF_ETC[@]}"; do
    if [ -e "$old/etc/$d" ] || [ -e "$new/etc/$d" ]; then
      local out
      out=$(diff -ruN "$old/etc/$d" "$new/etc/$d" 2>/dev/null || true)
      [ -z "$out" ] || { echo "=== /etc/$d"; printf '%s\n' "$out"; }
    fi
  done
}

# --- switch / confirm / revert ---------------------------------------------

run_switch() {
  local sys=$1 action=$2
  # WHY: a transient unit keeps the activation running if the SSH session
  # that started it dies when networking changes.
  systemd-run --quiet --wait --collect --unit="$SWITCH_UNIT-$$" \
    --property=Type=oneshot "$sys/bin/switch-to-configuration" "$action"
}

cmd_switch() {
  local timeout=$DEFAULT_TIMEOUT sys prev
  while [ $# -gt 0 ]; do
    case $1 in
      --timeout) timeout=${2:-}; shift 2 ;;
      --timeout=*) timeout=${1#*=}; shift ;;
      -*) die "unknown option $1" ;;
      *) break ;;
    esac
  done
  [[ $timeout =~ ^[0-9]+$ ]] && [ "$timeout" -ge 10 ] || die "--timeout must be a number of seconds >= 10"
  require_root
  sys=$(check_system "${1:-}")
  pending && die "a trial is already pending ($(cat "$STATE_DIR/new")); confirm or revert it first"
  prev=$(readlink -f /run/current-system)
  [ "$prev" != "$sys" ] || die "$sys is already the running system"

  mkdir -p "$STATE_DIR"
  printf '%s\n' "$prev" > "$STATE_DIR/previous"
  printf '%s\n' "$sys" > "$STATE_DIR/new"
  printf '%s\n' "$(( $(date +%s) + timeout ))" > "$STATE_DIR/deadline"

  # INVARIANT: arm the revert before activating, so a hung or fatal
  # activation still gets reverted.
  systemd-run --quiet --unit="$TIMER_UNIT" --on-active="${timeout}s" \
    --timer-property=AccuracySec=1s "$SELF" revert --from-timer

  log "trial: activating $sys; reverting to $prev in ${timeout}s unless confirmed"
  if ! run_switch "$sys" test; then
    log "activation of $sys reported errors; the revert is still armed"
  fi
  echo "Trial active. Run 'router-apply confirm' within ${timeout}s to keep it,"
  echo "or 'router-apply revert' to go back now."
}

cmd_confirm() {
  require_root
  pending || die "no trial pending"
  local sys; sys=$(cat "$STATE_DIR/new")
  systemctl stop "$TIMER_UNIT.timer" 2>/dev/null || true
  [ "$(readlink -f /run/current-system)" = "$sys" ] || die "running system is not the trial system $sys"
  nix-env -p "$PROFILE" --set "$sys"
  # boot: install the boot entry for the new default without reactivating.
  "$sys/bin/switch-to-configuration" boot
  rm -rf "$STATE_DIR"
  log "confirmed $sys as the boot default"
}

cmd_revert() {
  require_root
  local from_timer=0
  [ "${1:-}" = --from-timer ] && from_timer=1
  pending || { [ $from_timer = 1 ] && exit 0; die "no trial pending"; }
  local prev; prev=$(cat "$STATE_DIR/previous")
  [ $from_timer = 1 ] || systemctl stop "$TIMER_UNIT.timer" 2>/dev/null || true
  log "reverting to $prev$([ $from_timer = 1 ] && echo ' (not confirmed in time)')"
  # The profile never moved during the trial, so `test` restores the running
  # system and the boot default is already the previous generation.
  run_switch "$prev" test || log "revert activation reported errors"
  rm -rf "$STATE_DIR"
}

cmd_status() {
  if ! pending; then echo "No trial pending."; return 0; fi
  local left=$(( $(cat "$STATE_DIR/deadline") - $(date +%s) ))
  echo "Trial pending:"
  echo "  new:      $(cat "$STATE_DIR/new")"
  echo "  previous: $(cat "$STATE_DIR/previous")"
  echo "  reverts in ${left}s unless confirmed"
}

case ${1:-} in
  diff) shift; cmd_diff "$@" ;;
  switch) shift; cmd_switch "$@" ;;
  confirm) shift; cmd_confirm ;;
  revert) shift; cmd_revert "$@" ;;
  status) shift; cmd_status ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
