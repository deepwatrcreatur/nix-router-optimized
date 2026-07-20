#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

terminate_machine() {
  local machine="$1"
  if ! machinectl show "${machine}" >/dev/null 2>&1; then
    return 0
  fi

  machinectl terminate "${machine}"

  for _ in $(seq 1 20); do
    if ! machinectl show "${machine}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "machine still present after terminate: ${machine}" >&2
  return 1
}

delete_bridge() {
  local bridge="$1"
  if ! ip link show "${bridge}" >/dev/null 2>&1; then
    return 0
  fi

  ip link delete "${bridge}" type bridge

  if ip link show "${bridge}" >/dev/null 2>&1; then
    echo "bridge still present after delete: ${bridge}" >&2
    return 1
  fi
}

delete_nft_table() {
  if ! command -v nft >/dev/null 2>&1; then
    return 0
  fi

  if ! nft list table inet "${LAB_NFT_TABLE}" >/dev/null 2>&1; then
    return 0
  fi

  nft delete table inet "${LAB_NFT_TABLE}"

  if nft list table inet "${LAB_NFT_TABLE}" >/dev/null 2>&1; then
    echo "nft table still present after delete: ${LAB_NFT_TABLE}" >&2
    return 1
  fi
}

for machine in \
  "${LAB_MACHINE_ROUTER}" \
  "${LAB_MACHINE_BACKUP}" \
  "${LAB_MACHINE_WAN}" \
  "${LAB_MACHINE_CLIENT}"
do
  terminate_machine "${machine}"
done

delete_bridge "${LAB_LAN_BRIDGE}"
delete_bridge "${LAB_WAN_BRIDGE}"
delete_nft_table
