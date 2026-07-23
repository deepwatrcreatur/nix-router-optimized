#!/usr/bin/env bash
set -euo pipefail

LAB_PREFIX="lab-ha"
LAB_LAN_BRIDGE="${LAB_PREFIX}-lan"
LAB_WAN_BRIDGE="${LAB_PREFIX}-wan"
LAB_NFT_TABLE="${LAB_PREFIX}"
LAB_STATE_DIR="/run/${LAB_PREFIX}"
LAB_BRIDGE_NF_STATE_FILE="${LAB_STATE_DIR}/bridge-nf.env"
LAB_DEFAULT_ASSERT_TIMEOUT_SECONDS="${LAB_DEFAULT_ASSERT_TIMEOUT_SECONDS:-30}"
if [[ -x /run/current-system/sw/bin/chattr ]]; then
  LAB_CHATTR_BIN="/run/current-system/sw/bin/chattr"
elif [[ -x /usr/bin/chattr ]]; then
  LAB_CHATTR_BIN="/usr/bin/chattr"
elif [[ -x /bin/chattr ]]; then
  LAB_CHATTR_BIN="/bin/chattr"
else
  LAB_CHATTR_BIN=""
fi

LAB_MACHINE_ROUTER="lab-ha-router"
LAB_MACHINE_BACKUP="lab-ha-router-backup"
LAB_MACHINE_WAN="lab-ha-wan"
LAB_MACHINE_CLIENT="lab-ha-client"

LAB_LAN_HOST_LINKS=(
  lhrlan0
  lhblan0
  lhclan0
)

LAB_WAN_HOST_LINKS=(
  lhrwan0
  lhbwan0
  lhwwan0
)

LAB_LAN_GUEST_LINKS=(
  grlan0
  gblan0
  gclan0
)

LAB_WAN_GUEST_LINKS=(
  grwan0
  gbwan0
  gwwan0
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must run as root." >&2
    exit 1
  fi
}

validated_positive_integer() {
  local value="$1"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "expected positive decimal integer, got: ${value}" >&2
    return 1
  fi
  printf '%s\n' "${value}"
}

run_with_timeout() {
  local timeout_seconds_raw="$1"
  shift
  local timeout_seconds
  local pid
  local elapsed=0

  timeout_seconds="$(validated_positive_integer "${timeout_seconds_raw}")"

  (
    "$@"
  ) &
  pid=$!

  while kill -0 "${pid}" >/dev/null 2>&1; do
    if (( elapsed >= timeout_seconds )); then
      kill "${pid}" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "${pid}"
}

ensure_lab_name() {
  case "$1" in
    lab-ha-*) ;;
    *)
      echo "Refusing to operate on non-lab name: $1" >&2
      exit 1
      ;;
  esac
}

machine_leader() {
  machinectl show "$1" -p Leader --value
}

in_machine() {
  local machine="$1"
  shift
  local leader
  leader="$(machine_leader "${machine}")"
  nsenter -t "${leader}" -m -u -i -n -p -- "$@"
}

poll_until_true() {
  local timeout_seconds_raw="${1:-${LAB_DEFAULT_ASSERT_TIMEOUT_SECONDS}}"
  shift
  local timeout_seconds
  local deadline
  local attempt_timeout=5

  timeout_seconds="$(validated_positive_integer "${timeout_seconds_raw}")"
  deadline=$((SECONDS + timeout_seconds))

  if (( timeout_seconds < attempt_timeout )); then
    attempt_timeout="${timeout_seconds}"
  fi

  while (( SECONDS < deadline )); do
    if run_with_timeout "${attempt_timeout}" "$@"; then
      return 0
    fi
    sleep 1
  done

  return 1
}
