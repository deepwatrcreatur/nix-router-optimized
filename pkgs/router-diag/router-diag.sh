#!/usr/bin/env bash
set -euo pipefail

# router-diag: Operational Diagnostics CLI for NixOS Router
# VyOS-inspired "show" commands for terminal-based debugging

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_usage() {
    echo "Usage: router-diag <command> [subcommand]"
    echo ""
    echo "Commands:"
    echo "  show interfaces    Display interface status and IP addresses"
    echo "  show firewall      Summary of active nftables chains and hits"
    echo "  show vpn           WireGuard and Tailscale status"
    echo "  show health        Explicit health check results"
    echo "  help               Display this help message"
}

function show_interfaces() {
    echo -e "${YELLOW}--- Interface Status ---${NC}"
    ip -4 -brief addr show
    echo ""
    echo -e "${YELLOW}--- Carrier Status ---${NC}"
    for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
        if [ "$iface" != "lo" ]; then
            state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
            echo -n "  $iface: "
            if [ "$state" == "up" ]; then
                echo -e "${GREEN}$state${NC}"
            else
                echo -e "${RED}$state${NC}"
            fi
        fi
    done
}

function show_firewall() {
    echo -e "${YELLOW}--- Firewall Summary (nftables) ---${NC}"
    if command -v nft >/dev/null; then
        echo "Active tables:"
        nft list tables
        echo ""
        echo "Ruleset statistics (non-zero counters):"
        nft list ruleset | grep -E "counter packets [1-9]" || echo "No active counters found."
    else
        echo -e "${RED}Error: nft command not found.${NC}"
    fi
}

function show_vpn() {
    echo -e "${YELLOW}--- VPN Status (WireGuard) ---${NC}"
    if command -v wg >/dev/null; then
        sudo wg show || echo "No active WireGuard interfaces."
    else
        echo "wg command not found."
    fi
    echo ""
    echo -e "${YELLOW}--- VPN Status (Tailscale) ---${NC}"
    if command -v tailscale >/dev/null; then
        tailscale status || echo "Tailscale not running."
    else
        echo "tailscale command not found."
    fi
}

function show_health() {
    echo -e "${YELLOW}--- Router Health Checks ---${NC}"
    # Derived from Task 05 health check services
    services=(
        "health-mgmt-ip"
        "health-lan-ip"
        "health-wan-carrier"
        "health-wan-ip"
    )
    
    for svc in "${services[@]}"; do
        echo -n "  $svc: "
        if systemctl is-active --quiet "$svc"; then
            echo -e "${GREEN}PASS${NC}"
        else
            echo -e "${RED}FAIL${NC}"
            systemctl status "$svc" --no-pager | grep -E "Active:|Main PID:" | sed 's/^/    /'
        fi
    done
}

# Main entry point
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

case "$1" in
    show)
        if [ $# -lt 2 ]; then
            show_usage
            exit 1
        fi
        case "$2" in
            interfaces) show_interfaces ;;
            firewall)   show_firewall ;;
            vpn)        show_vpn ;;
            health)     show_health ;;
            *)          show_usage; exit 1 ;;
        esac
        ;;
    help)
        show_usage
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
