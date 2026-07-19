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

boot_one() {
  local attr="$1"
  local machine="$2"
  local bridge_lan="$3"
  local bridge_wan="$4"
  local root
  local -a args
  ensure_lab_name "$machine"
  root="$(closure_path "$attr")"
  args=(
    --quiet
    --boot
    --directory="${root}"
    --machine="${machine}"
    --network-bridge="${bridge_lan}"
    --network-zone="${LAB_PREFIX}"
    --bind-ro=/nix/store
  )
  if [[ -n "${bridge_wan}" ]]; then
    args+=(--network-bridge="${bridge_wan}")
  fi
  systemd-nspawn "${args[@]}"
}

boot_one "lab-router" "${LAB_MACHINE_ROUTER}" "${LAB_LAN_BRIDGE}" "${LAB_WAN_BRIDGE}"
boot_one "lab-router-backup" "${LAB_MACHINE_BACKUP}" "${LAB_LAN_BRIDGE}" "${LAB_WAN_BRIDGE}"
boot_one "lab-wan" "${LAB_MACHINE_WAN}" "${LAB_WAN_BRIDGE}" ""
boot_one "lab-client" "${LAB_MACHINE_CLIENT}" "${LAB_LAN_BRIDGE}" ""
