# 06 VPN Module Smoke Tests

Status: `ready`

Suggested branch: `feat/router-vpn-smoke-tests`

## Goal

Add smoke coverage for the VPN wrapper modules so they fail early in CI when
their option wiring or firewall integration drifts.

## Why This Matters

The repo now has router-aware wrappers for:

- `router-wireguard`
- `router-openvpn`
- `router-tailscale`

But there is no automated coverage proving they still evaluate cleanly in the
common integration cases documented by the repo.

## Scope

- add evaluation-oriented tests for `router-wireguard`
- add evaluation-oriented tests for `router-openvpn`
- add evaluation-oriented tests for `router-tailscale`

## Minimum Cases To Cover

### `router-wireguard`

- enabled with the minimum required key configuration
- `routeToWan = true` with a valid WAN source path
- `routeToWan = true` with no derived WAN interfaces
  - this should either warn, assert, or otherwise become visible instead of
    silently behaving like a no-op

### `router-openvpn`

- one instance with WAN exposure
- multiple instances with distinct interface names
- a duplicate-interface case if you choose to validate this explicitly

### `router-tailscale`

- enabled with `router-firewall` present
- enabled without `router-firewall`
- ensure the optional integration path stays composable instead of hard-failing

## Non-Goals

- real tunnel establishment
- network namespace or end-to-end VPN traffic tests

## Validation

- CI exercises the three wrapper modules in representative configurations
- silent-no-op cases become visible to maintainers
