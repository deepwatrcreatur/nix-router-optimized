# 06 VPN Module Smoke Tests

Status: `done`

Suggested branch: `feat/router-vpn-smoke-tests`

## Goal

Add smoke coverage for the VPN wrapper modules so they fail early in CI when
their option wiring or firewall integration drifts.

## Why This Matters

The repo now has router-aware wrappers for:

- `router-wireguard`
- `router-openvpn`
- `router-tailscale`
- `router-netbird`

But there is no automated coverage proving they still evaluate cleanly in the
common integration cases documented by the repo.

## Scope

- add evaluation-oriented tests for `router-wireguard`
- add evaluation-oriented tests for `router-openvpn`
- add evaluation-oriented tests for `router-tailscale`
- add evaluation-oriented tests for `router-netbird`

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

### `router-netbird`

- enabled with `router-firewall` present
- enabled without `router-firewall`
- enabled alongside `router-tailscale` (dual-overlay case, no port collision)
  and assert the merged `services.router-firewall.overlayInterfaces` contains
  both overlay interface names
- port collision assertion fires when both modules use the same port
- `dnsResolverAddress` set — check the env var is threaded through correctly
- `setupKeyFile` set — ensure the login block appears in the client config

## Non-Goals

- real tunnel establishment
- network namespace or end-to-end VPN traffic tests

## Validation

- CI exercises all four wrapper modules in representative configurations
- the dual-overlay (Tailscale + Netbird) case evaluates cleanly
- the dual-overlay case proves both wrappers registered their overlay
  interfaces with `router-firewall`
- silent-no-op cases become visible to maintainers
