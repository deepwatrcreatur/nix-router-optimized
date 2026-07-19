#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scenario="${1:-}"
if [[ -z "${scenario}" ]]; then
  echo "usage: $0 <vip-single-owner|single-active-demo-unit>" >&2
  exit 1
fi

case "${scenario}" in
  vip-single-owner)
    exec "${script_dir}/../scenarios/assert-vip-single-owner.sh"
    ;;
  single-active-demo-unit)
    exec "${script_dir}/../scenarios/assert-single-active-demo-unit.sh"
    ;;
  *)
    echo "unknown scenario: ${scenario}" >&2
    exit 1
    ;;
esac
