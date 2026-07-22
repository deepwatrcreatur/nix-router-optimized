#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

require_root

repo_root="$(cd "${script_dir}/../../.." && pwd)"

closure_path() {
  nix build --no-link --print-out-paths "${repo_root}#nixosConfigurations.$1.config.system.build.images.lxc"
}

tarball_path() {
  local image_root
  image_root="$(closure_path "$1")"
  find "${image_root}/tarball" -maxdepth 1 -type f -name '*.tar.xz' | head -n 1
}

rootfs_dir_for() {
  local machine="$1"
  local machine_dir="${LAB_STATE_DIR}/${machine}"
  mkdir -p "${machine_dir}"
  local root_dir
  root_dir="$(mktemp -d "${machine_dir}/root.XXXXXX")"
  chmod 0755 "${root_dir}"
  printf '%s\n' "${root_dir}"
}

extract_rootfs() {
  local attr="$1"
  local machine="$2"
  local tarball
  local root_dir

  tarball="$(tarball_path "$attr")"
  if [[ -z "${tarball}" ]]; then
    echo "Could not locate LXC tarball for ${attr}" >&2
    return 1
  fi

  root_dir="$(rootfs_dir_for "${machine}")"
  tar -xJf "${tarball}" -C "${root_dir}"
  printf '%s\n' "${root_dir}"
}

wait_for_link() {
  local link_name="$1"
  local timeout_seconds="${2:-15}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if ip link show "${link_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for link to appear: ${link_name}" >&2
  return 1
}

settle_link() {
  local link_name="$1"
  local settle_timeout="${2:-5}"

  wait_for_link "${link_name}" "${settle_timeout}"
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle --timeout="${settle_timeout}" --exit-if-exists="/sys/class/net/${link_name}" >/dev/null 2>&1 || true
  fi
}

delete_link_if_present() {
  local link_name="$1"
  ip link delete "${link_name}" >/dev/null 2>&1 || true
}

lan_host_if_for() {
  case "$1" in
    "${LAB_MACHINE_ROUTER}")
      echo "lhrlan0"
      ;;
    "${LAB_MACHINE_BACKUP}")
      echo "lhblan0"
      ;;
    "${LAB_MACHINE_CLIENT}")
      echo "lhclan0"
      ;;
    *)
      echo "No LAN host veth mapping defined for machine: $1" >&2
      return 1
      ;;
  esac
}

lan_guest_if_for() {
  case "$1" in
    "${LAB_MACHINE_ROUTER}")
      echo "grlan0"
      ;;
    "${LAB_MACHINE_BACKUP}")
      echo "gblan0"
      ;;
    "${LAB_MACHINE_CLIENT}")
      echo "gclan0"
      ;;
    *)
      echo "No LAN guest veth mapping defined for machine: $1" >&2
      return 1
      ;;
  esac
}

wan_host_if_for() {
  case "$1" in
    "${LAB_MACHINE_ROUTER}")
      echo "lhrwan0"
      ;;
    "${LAB_MACHINE_BACKUP}")
      echo "lhbwan0"
      ;;
    "${LAB_MACHINE_WAN}")
      echo "lhwwan0"
      ;;
    *)
      echo "No WAN host veth mapping defined for machine: $1" >&2
      return 1
      ;;
  esac
}

wan_guest_if_for() {
  case "$1" in
    "${LAB_MACHINE_ROUTER}")
      echo "grwan0"
      ;;
    "${LAB_MACHINE_BACKUP}")
      echo "gbwan0"
      ;;
    "${LAB_MACHINE_WAN}")
      echo "gwwan0"
      ;;
    *)
      echo "No WAN guest veth mapping defined for machine: $1" >&2
      return 1
      ;;
  esac
}

attach_link_to_bridge() {
  local host_if="$1"
  local bridge="$2"
  wait_for_link "${host_if}"
  ip link set "${host_if}" master "${bridge}"
  ip link set "${host_if}" up
}

create_attached_veth_pair() {
  local host_if="$1"
  local guest_if="$2"
  local bridge="$3"
  delete_link_if_present "${host_if}"
  delete_link_if_present "${guest_if}"
  ip link add "${host_if}" type veth peer name "${guest_if}"
  settle_link "${host_if}"
  settle_link "${guest_if}"
  attach_link_to_bridge "${host_if}" "${bridge}"
  ip link set "${guest_if}" up
  settle_link "${guest_if}"
  sleep 1
}

boot_one() {
  local attr="$1"
  local machine="$2"
  local root
  local unit
  local lan_host_if=""
  local lan_guest_if=""
  local wan_host_if=""
  local wan_guest_if=""
  local -a args run_args
  ensure_lab_name "$machine"
  root="$(extract_rootfs "$attr" "$machine")"
  unit="lab-nspawn-${machine}.service"
  systemctl stop "${unit}" >/dev/null 2>&1 || true
  systemctl reset-failed "${unit}" >/dev/null 2>&1 || true
  args=(
    --quiet
    --boot
    --directory="${root}"
    --machine="${machine}"
    --bind-ro=/nix/store
  )

  case "${machine}" in
    "${LAB_MACHINE_ROUTER}"|"${LAB_MACHINE_BACKUP}")
      lan_host_if="$(lan_host_if_for "${machine}")"
      lan_guest_if="$(lan_guest_if_for "${machine}")"
      wan_host_if="$(wan_host_if_for "${machine}")"
      wan_guest_if="$(wan_guest_if_for "${machine}")"
      create_attached_veth_pair "${lan_host_if}" "${lan_guest_if}" "${LAB_LAN_BRIDGE}"
      create_attached_veth_pair "${wan_host_if}" "${wan_guest_if}" "${LAB_WAN_BRIDGE}"
      args+=(
        --network-interface="${lan_guest_if}:host0"
        --network-interface="${wan_guest_if}:host1"
      )
      ;;
    "${LAB_MACHINE_CLIENT}")
      lan_host_if="$(lan_host_if_for "${machine}")"
      lan_guest_if="$(lan_guest_if_for "${machine}")"
      create_attached_veth_pair "${lan_host_if}" "${lan_guest_if}" "${LAB_LAN_BRIDGE}"
      args+=(--network-interface="${lan_guest_if}:host0")
      ;;
    "${LAB_MACHINE_WAN}")
      wan_host_if="$(wan_host_if_for "${machine}")"
      wan_guest_if="$(wan_guest_if_for "${machine}")"
      create_attached_veth_pair "${wan_host_if}" "${wan_guest_if}" "${LAB_WAN_BRIDGE}"
      args+=(--network-interface="${wan_guest_if}:host0")
      ;;
    *)
      echo "Unhandled lab machine: ${machine}" >&2
      return 1
      ;;
  esac

  run_args=(
    --quiet
    --unit="${unit}"
    --property=Type=exec
    --property=KillMode=mixed
    systemd-nspawn
  )
  run_args+=("${args[@]}")
  systemd-run "${run_args[@]}"
}

boot_one "lab-router" "${LAB_MACHINE_ROUTER}"
boot_one "lab-router-backup" "${LAB_MACHINE_BACKUP}"
boot_one "lab-wan" "${LAB_MACHINE_WAN}"
boot_one "lab-client" "${LAB_MACHINE_CLIENT}"
