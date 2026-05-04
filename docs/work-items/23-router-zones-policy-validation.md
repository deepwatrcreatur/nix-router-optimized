# Router Zones Policy Validation

Status: `ready`
Priority: `high`
Branch: `fix/router-zones-policy-validation`

## Goal

Finish the staged `router-zones` policy engine so it is safe to export and
document.

## Why

Interrupted work added `modules/router-zones.nix`, but it was marked complete
before validation. The module now uses the repaired table-scope firewall hook,
but it still needs policy validation and tests before it should be consumed by
downstream router configurations.

## Scope

- Add assertions that every policy `fromZone` and `toZone` exists in
  `services.router-zones.zones`.
- Define behavior for empty `extraRules`; avoid generating invalid nftables
  rules such as an `oifname` prefix without an action.
- Decide whether `defaultInputPolicy` is implemented or remove/defer it from
  the public option surface.
- Add eval tests for basic LAN/WAN, IoT isolation, and invalid zone
  references.
- Verify generated nftables syntax for policy combinations.

## Non-Goals

- Replacing the existing role-aware router firewall.
- Designing a full GUI/API for zone management.
- Enabling zones in downstream configurations.

## Validation

- Targeted NixOS eval tests pass.
- `nix flake check --no-build` gets past router-zones tests.
- `git diff --check` is clean.

