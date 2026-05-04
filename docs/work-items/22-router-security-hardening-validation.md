# Router Security Hardening Validation

Status: `ready`
Priority: `high`
Branch: `fix/router-security-hardening-validation`

## Goal

Turn the staged `router-security-hardened` module into a reviewed,
evaluation-tested module with clear firewall integration semantics.

## Why

Interrupted work added `modules/router-security-hardened.nix` and exported it
from the flake, but the first local validation failed because the module used a
nonexistent `services.router-firewall.extraRules` option. The immediate repair
added a table-scope firewall extension point, but the module still needs a
focused validation pass before it should be treated as complete.

## Scope

- Validate `services.router-firewall.extraFilterTableRules` as the correct API
  for declaring nftables sets and helper chains.
- Add or update eval tests covering:
  - kernel hardening only
  - Geo-IP blocking
  - MAC security in `alert` and `enforce` modes
- Verify generated nftables syntax for empty and non-empty country/MAC lists.
- Decide whether Geo-IP population should fail closed or tolerate download
  failures.
- Update README/release notes only after tests pass.

## Non-Goals

- Enabling hardening by default.
- Adding a full Geo-IP provider abstraction.
- Changing existing router-firewall policy defaults.

## Validation

- `nix flake check --no-build` or targeted eval checks pass without missing
  option errors.
- Generated nftables ruleset parses for representative configurations.
- `git diff --check` is clean.

