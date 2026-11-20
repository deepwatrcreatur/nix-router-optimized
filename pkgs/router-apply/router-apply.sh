# router-apply: commit-confirm style switching for NixOS routers.
# WHY: docs/router-apply-safety.md#automatic-revert-router-apply
#
# INVARIANT: during a trial the new system is activated with
# `switch-to-configuration test`, so the system profile and boot entry still
# point at the previous generation. A crash or reboot before `confirm` comes
# back on the old system; only `confirm` makes the new one the boot default.

STATE_DIR=${ROUTER_APPLY_STATE_DIR:-/run/router-apply}
PROFILE=${ROUTER_APPLY_PROFILE:-/nix/var/nix/profiles/system}
LOCK=${ROUTER_APPLY_LOCK:-/run/router-apply.lock}
TIMER_UNIT=router-apply-revert
# INVARIANT: fixed names, so revert can stop a hung trial activation.
TRIAL_UNIT=router-apply-trial
REVERT_UNIT=router-apply-restore
DEFAULT_TIMEOUT=${ROUTER_APPLY_DEFAULT_TIMEOUT:-300}
SELF=$(readlink -f "$0")

# Units whose rendered configuration `diff` expands, and /etc trees it diffs.
DIFF_UNITS=(nftables keepalived kea-dhcp4-server kea-dhcp6-server kea-dhcp-ddns-server
  systemd-networkd technitium-dns-server frr radvd chronyd)
if [ -n "${ROUTER_APPLY_DIFF_UNITS:-}" ]; then
  read -r -a DIFF_UNITS <<< "$ROUTER_APPLY_DIFF_UNITS"
fi
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

# WHY: switch, confirm and revert check and change state in several steps;
# the lock keeps two of them (or the timer) from interleaving.
take_lock() {
  exec 9>"$LOCK"
  flock 9
}

# --- diff -------------------------------------------------------------------

store_name() { basename "$1" | cut -d- -f2-; }

# Text files under /nix/store referenced by $1, one level deep.
referenced_files() {
  # GOTCHA: a file with no store references is a normal leaf; grep's exit 1
  # must not abort the diff under errexit/pipefail.
  { grep -oE '/nix/store/[a-z0-9]{32}-[^ "'\''`;:)]+' "$1" 2>/dev/null || true; } | sort -u | while read -r p; do
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
    op=$(while read -r p; do
      if [ "$(store_name "$p")" = "$name" ]; then echo "$p"; break; fi
    done < "$tmp/old")
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
  local unit=$1 sys=$2 action=$3
  # WHY: a transient unit keeps the activation running if the SSH session
  # that started it dies when networking changes.
  systemd-run --quiet --wait --collect --unit="$unit" \
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
  take_lock
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
  # Release before activating: the timer's revert must be able to take the
  # lock and stop a hung activation.
  exec 9>&-

  log "trial: activating $sys; reverting to $prev in ${timeout}s unless confirmed"
  if ! run_switch "$TRIAL_UNIT" "$sys" test; then
    log "activation of $sys reported errors; the revert is still armed"
  fi
  echo "Trial active. Run 'router-apply confirm' within ${timeout}s to keep it,"
  echo "or 'router-apply revert' to go back now."
}

cmd_confirm() {
  require_root
  take_lock
  pending || die "no trial pending"
  local sys prev trial_running
  sys=$(cat "$STATE_DIR/new")
  prev=$(cat "$STATE_DIR/previous")
  # INVARIANT: every check and fallible step comes before the timer stops,
  # so a failed confirm leaves the automatic revert armed.
  # GOTCHA: a running oneshot is "activating", which is-active reports as
  # inactive.
  case $(systemctl show -P ActiveState "$TRIAL_UNIT.service" 2>/dev/null) in
    active|activating|reloading|deactivating) trial_running=1 ;;
    *) trial_running=0 ;;
  esac
  if [ "$trial_running" = 1 ]; then
    die "the trial activation is still running; wait for it, then confirm (the revert stays armed)"
  fi
  [ "$(readlink -f /run/current-system)" = "$sys" ] \
    || die "running system is not the trial system $sys (the revert stays armed)"
  nix-env -p "$PROFILE" --set "$sys"
  # boot: install the boot entry for the new default without reactivating.
  if ! "$sys/bin/switch-to-configuration" boot; then
    nix-env -p "$PROFILE" --set "$prev" || true
    "$prev/bin/switch-to-configuration" boot || true
    die "installing the boot entry failed; profile restored to $prev and the revert stays armed"
  fi
  systemctl stop "$TIMER_UNIT.timer" 2>/dev/null || true
  rm -rf "$STATE_DIR"
  log "confirmed $sys as the boot default"
}

cmd_revert() {
  require_root
  local from_timer=0
  [ "${1:-}" = --from-timer ] && from_timer=1
  take_lock
  if ! pending; then
    [ $from_timer = 1 ] && exit 0
    die "no trial pending"
  fi
  local prev; prev=$(cat "$STATE_DIR/previous")
  [ $from_timer = 1 ] || systemctl stop "$TIMER_UNIT.timer" 2>/dev/null || true
  log "reverting to $prev$([ $from_timer = 1 ] && echo ' (not confirmed in time)')"
  # WHY: a hung trial activation holds switch-to-configuration's lock; stop
  # it first, or the revert's activation would fail at once.
  systemctl stop "$TRIAL_UNIT.service" 2>/dev/null || true
  # The profile never moved during the trial, so `test` restores the running
  # system and the boot default is already the previous generation.
  local attempt
  for attempt in 1 2 3 4 5; do
    if run_switch "$REVERT_UNIT" "$prev" test; then
      rm -rf "$STATE_DIR"
      log "reverted to $prev"
      return 0
    fi
    log "revert attempt $attempt failed; retrying in 10s"
    sleep 10
  done
  # Keep the state so `router-apply revert` can be retried by hand.
  die "could not reactivate $prev; state kept in $STATE_DIR, run 'router-apply revert' or reboot (the boot default is $prev)"
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
