#!/usr/bin/env bash
set -euo pipefail

LAB_PREFIX="lab-ha"
LAB_LAN_BRIDGE="${LAB_PREFIX}-lan"
LAB_WAN_BRIDGE="${LAB_PREFIX}-wan"
LAB_NFT_TABLE="${LAB_PREFIX}"

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
