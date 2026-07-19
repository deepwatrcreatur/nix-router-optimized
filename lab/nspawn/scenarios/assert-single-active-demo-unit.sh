#!/usr/bin/env bash
set -euo pipefail

service="router-lab-owner-demo.service"
router_active=0
backup_active=0

if machinectl shell lab-ha-router /bin/sh -lc "systemctl is-active --quiet ${service}"; then
  router_active=1
fi

if machinectl shell lab-ha-router-backup /bin/sh -lc "systemctl is-active --quiet ${service}"; then
  backup_active=1
fi

if [[ $((router_active + backup_active)) -ne 1 ]]; then
  echo "expected ${service} to be active on exactly one router node" >&2
  echo "router=${router_active} backup=${backup_active}" >&2
  exit 1
fi

echo "${service} is single-active"
