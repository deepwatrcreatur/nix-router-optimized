#!/usr/bin/env bash
set -euo pipefail

vip="192.0.2.1"
machines=(
  "lab-ha-router"
  "lab-ha-router-backup"
)

owners=0

for machine in "${machines[@]}"; do
  if machinectl shell "${machine}" /bin/sh -lc "ip -o addr show dev host0 | grep -q '${vip}'"; then
    owners=$((owners + 1))
  fi
done

if [[ "${owners}" -ne 1 ]]; then
  echo "expected exactly one VIP owner for ${vip}, found ${owners}" >&2
  exit 1
fi

echo "VIP ${vip} is singly owned"
