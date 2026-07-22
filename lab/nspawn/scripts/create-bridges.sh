#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

save_and_disable_bridge_nf() {
  local current_iptables current_ip6tables current_arptables
  mkdir -p "${LAB_STATE_DIR}"
  current_iptables="$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)"
  current_ip6tables="$(sysctl -n net.bridge.bridge-nf-call-ip6tables 2>/dev/null || echo 0)"
  current_arptables="$(sysctl -n net.bridge.bridge-nf-call-arptables 2>/dev/null || echo 0)"
  cat > "${LAB_BRIDGE_NF_STATE_FILE}" <<EOF
BRIDGE_NF_IPTABLES=${current_iptables}
BRIDGE_NF_IP6TABLES=${current_ip6tables}
BRIDGE_NF_ARPTABLES=${current_arptables}
EOF
  sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
  sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
  sysctl -w net.bridge.bridge-nf-call-arptables=0 >/dev/null 2>&1 || true
}

ip link show "${LAB_LAN_BRIDGE}" >/dev/null 2>&1 || ip link add "${LAB_LAN_BRIDGE}" type bridge
ip link show "${LAB_WAN_BRIDGE}" >/dev/null 2>&1 || ip link add "${LAB_WAN_BRIDGE}" type bridge

ip link set "${LAB_LAN_BRIDGE}" up
ip link set "${LAB_WAN_BRIDGE}" up

save_and_disable_bridge_nf
