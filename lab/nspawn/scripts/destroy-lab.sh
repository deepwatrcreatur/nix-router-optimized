#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

terminate_machine() {
  local machine="$1"
  local unit="lab-nspawn-${machine}.service"

  systemctl stop "${unit}" >/dev/null 2>&1 || true
  systemctl reset-failed "${unit}" >/dev/null 2>&1 || true

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

restore_bridge_nf() {
  if [[ ! -f "${LAB_BRIDGE_NF_STATE_FILE}" ]]; then
    return 0
  fi

  # shellcheck disable=SC1090
  source "${LAB_BRIDGE_NF_STATE_FILE}"
  sysctl -w net.bridge.bridge-nf-call-iptables="${BRIDGE_NF_IPTABLES}" >/dev/null 2>&1 || true
  sysctl -w net.bridge.bridge-nf-call-ip6tables="${BRIDGE_NF_IP6TABLES}" >/dev/null 2>&1 || true
  sysctl -w net.bridge.bridge-nf-call-arptables="${BRIDGE_NF_ARPTABLES}" >/dev/null 2>&1 || true
}

delete_lab_link() {
  local link="$1"
  ip link delete "${link}" >/dev/null 2>&1 || true
}

delete_leftover_links() {
  local -a links=(
    lhrlan0 lhblan0 lhclan0
    lhrwan0 lhbwan0 lhwwan0
    grlan0 gblan0 gclan0
    grwan0 gbwan0 gwwan0
  )
  local link
  for link in "${links[@]}"; do
    delete_lab_link "${link}"
  done
}

delete_state_dir() {
  local -a mountpoints=()
  local -a immutable_candidates=()
  local idx
  local path

  if [[ ! -d "${LAB_STATE_DIR}" ]]; then
    return 0
  fi

  mapfile -t mountpoints < <(findmnt -R -n -o TARGET "${LAB_STATE_DIR}" 2>/dev/null || true)
  for (( idx=${#mountpoints[@]} - 1; idx >= 0; idx-- )); do
    umount "${mountpoints[$idx]}" >/dev/null 2>&1 || true
  done

  if [[ -n "${LAB_CHATTR_BIN}" ]]; then
    mapfile -t immutable_candidates < <(find "${LAB_STATE_DIR}" -type d \( -path '*/root.*/var/empty' -o -path '*/root.*/var/empty/*' \) 2>/dev/null || true)
    for path in "${immutable_candidates[@]}"; do
      "${LAB_CHATTR_BIN}" -i "${path}" >/dev/null 2>&1 || true
    done
  fi
  rm -rf -- "${LAB_STATE_DIR}" >/dev/null 2>&1 || true

  if [[ -e "${LAB_STATE_DIR}" ]]; then
    echo "lab state directory still present after delete: ${LAB_STATE_DIR}" >&2
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
delete_leftover_links
restore_bridge_nf
delete_nft_table
delete_state_dir
