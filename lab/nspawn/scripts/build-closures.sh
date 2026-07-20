#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

build_one() {
  local attr="$1"
  echo "==> Building $attr"
  nix build "${repo_root}#nixosConfigurations.${attr}.config.system.build.toplevel"
}

build_one "lab-router"
build_one "lab-router-backup"
build_one "lab-wan"
build_one "lab-client"
