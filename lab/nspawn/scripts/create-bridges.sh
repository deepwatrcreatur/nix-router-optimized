#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

ip link show "${LAB_LAN_BRIDGE}" >/dev/null 2>&1 || ip link add "${LAB_LAN_BRIDGE}" type bridge
ip link show "${LAB_WAN_BRIDGE}" >/dev/null 2>&1 || ip link add "${LAB_WAN_BRIDGE}" type bridge

ip link set "${LAB_LAN_BRIDGE}" up
ip link set "${LAB_WAN_BRIDGE}" up

if command -v nft >/dev/null 2>&1; then
  nft list table inet "${LAB_NFT_TABLE}" >/dev/null 2>&1 || nft add table inet "${LAB_NFT_TABLE}"
  nft list chain inet "${LAB_NFT_TABLE}" forward >/dev/null 2>&1 || nft add chain inet "${LAB_NFT_TABLE}" forward "{ type filter hook forward priority 0; policy accept; }"
  nft list chain inet "${LAB_NFT_TABLE}" output >/dev/null 2>&1 || nft add chain inet "${LAB_NFT_TABLE}" output "{ type filter hook output priority 0; policy accept; }"
  nft flush chain inet "${LAB_NFT_TABLE}" forward
  nft add rule inet "${LAB_NFT_TABLE}" forward iifname "${LAB_LAN_BRIDGE}" drop
  nft add rule inet "${LAB_NFT_TABLE}" forward iifname "${LAB_WAN_BRIDGE}" drop
fi
