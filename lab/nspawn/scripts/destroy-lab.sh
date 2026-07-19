#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

for machine in \
  "${LAB_MACHINE_ROUTER}" \
  "${LAB_MACHINE_BACKUP}" \
  "${LAB_MACHINE_WAN}" \
  "${LAB_MACHINE_CLIENT}"
do
  machinectl terminate "${machine}" >/dev/null 2>&1 || true
done

ip link delete "${LAB_LAN_BRIDGE}" type bridge >/dev/null 2>&1 || true
ip link delete "${LAB_WAN_BRIDGE}" type bridge >/dev/null 2>&1 || true

if command -v nft >/dev/null 2>&1; then
  nft delete table inet "${LAB_NFT_TABLE}" >/dev/null 2>&1 || true
fi
