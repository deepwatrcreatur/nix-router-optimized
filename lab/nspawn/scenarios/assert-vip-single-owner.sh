#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "${script_dir}/../scripts/lib.sh"

require_root

vip="192.0.2.1"
machines=(
  "lab-ha-router"
  "lab-ha-router-backup"
)
timeout_seconds="${LAB_ASSERT_TIMEOUT_SECONDS:-${LAB_DEFAULT_ASSERT_TIMEOUT_SECONDS:-30}}"

count_owners() {
  local owners=0
  local machine

  for machine in "${machines[@]}"; do
    if in_machine "${machine}" bash -lc "ip -o addr show dev host0 | grep -F -q '${vip}/'"; then
      owners=$((owners + 1))
    fi
  done

  printf '%s\n' "${owners}"
}

vip_is_singly_owned() {
  local owners
  owners="$(count_owners)"
  [[ "${owners}" -eq 1 ]]
}

if poll_until_true "${timeout_seconds}" vip_is_singly_owned; then
  echo "VIP ${vip} is singly owned"
  exit 0
fi

owners="$(count_owners)"
echo "expected exactly one VIP owner for ${vip}, found ${owners}" >&2
exit 1
