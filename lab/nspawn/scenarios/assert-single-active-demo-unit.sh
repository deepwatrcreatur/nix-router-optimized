#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
source "${script_dir}/../scripts/lib.sh"

require_root

service="router-lab-owner-demo.service"
timeout_seconds="${LAB_ASSERT_TIMEOUT_SECONDS:-30}"
deadline=$((SECONDS + timeout_seconds))

count_active() {
  local router_active=0
  local backup_active=0

  if in_machine lab-ha-router bash -lc "systemctl is-active --quiet ${service}"; then
    router_active=1
  fi

  if in_machine lab-ha-router-backup bash -lc "systemctl is-active --quiet ${service}"; then
    backup_active=1
  fi

  printf '%s %s\n' "${router_active}" "${backup_active}"
}

while (( SECONDS < deadline )); do
  read -r router_active backup_active < <(count_active)
  if [[ $((router_active + backup_active)) -eq 1 ]]; then
    echo "${service} is single-active"
    exit 0
  fi
  sleep 1
done

read -r router_active backup_active < <(count_active)
echo "expected ${service} to be active on exactly one router node" >&2
echo "router=${router_active} backup=${backup_active}" >&2
exit 1
