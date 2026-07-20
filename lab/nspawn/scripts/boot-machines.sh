#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

repo_root="$(cd "${script_dir}/../../.." && pwd)"

closure_path() {
  nix build --no-link --print-out-paths "${repo_root}#nixosConfigurations.$1.config.system.build.toplevel"
}

wan_host_if_for() {
  local machine="$1"
  machine="${machine#lab-ha-}"
  echo "lab-ha-w-${machine}"
}

boot_one() {
  local attr="$1"
  local machine="$2"
  local bridge_lan="$3"
  local bridge_wan="$4"
  local root
  local unit
  local wan_host_if
  local -a args run_args
  ensure_lab_name "$machine"
  root="$(closure_path "$attr")"
  unit="lab-nspawn-${machine}.service"
  args=(
    --quiet
    --boot
    --directory="${root}"
    --machine="${machine}"
    --network-bridge="${bridge_lan}"
    --bind-ro=/nix/store
  )
  if [[ -n "${bridge_wan}" ]]; then
    wan_host_if="$(wan_host_if_for "${machine}")"
    args+=(--network-veth-extra="${wan_host_if}:host1")
  fi
  run_args=(
    --quiet
    --unit="${unit}"
    --property=Type=exec
    --property=KillMode=mixed
    systemd-nspawn
  )
  run_args+=("${args[@]}")
  systemd-run "${run_args[@]}"

  if [[ -n "${bridge_wan}" ]]; then
    ip link set "${wan_host_if}" master "${bridge_wan}"
    ip link set "${wan_host_if}" up
  fi
}

boot_one "lab-router" "${LAB_MACHINE_ROUTER}" "${LAB_LAN_BRIDGE}" "${LAB_WAN_BRIDGE}"
boot_one "lab-router-backup" "${LAB_MACHINE_BACKUP}" "${LAB_LAN_BRIDGE}" "${LAB_WAN_BRIDGE}"
boot_one "lab-wan" "${LAB_MACHINE_WAN}" "${LAB_WAN_BRIDGE}" ""
boot_one "lab-client" "${LAB_MACHINE_CLIENT}" "${LAB_LAN_BRIDGE}" ""
