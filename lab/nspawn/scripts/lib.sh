#!/usr/bin/env bash
set -euo pipefail

LAB_PREFIX="lab-ha"
LAB_LAN_BRIDGE="${LAB_PREFIX}-lan"
LAB_WAN_BRIDGE="${LAB_PREFIX}-wan"
LAB_NFT_TABLE="${LAB_PREFIX}"
LAB_STATE_DIR="/run/${LAB_PREFIX}"
LAB_BRIDGE_NF_STATE_FILE="${LAB_STATE_DIR}/bridge-nf.env"
if command -v chattr >/dev/null 2>&1; then
  LAB_CHATTR_BIN="$(command -v chattr)"
elif [[ -n "${SUDO_USER:-}" && -x "/home/${SUDO_USER}/.nix-profile/bin/chattr" ]]; then
  LAB_CHATTR_BIN="/home/${SUDO_USER}/.nix-profile/bin/chattr"
else
  LAB_CHATTR_BIN=""
fi

LAB_MACHINE_ROUTER="lab-ha-router"
LAB_MACHINE_BACKUP="lab-ha-router-backup"
LAB_MACHINE_WAN="lab-ha-wan"
LAB_MACHINE_CLIENT="lab-ha-client"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must run as root." >&2
    exit 1
  fi
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
