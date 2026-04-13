# 09 router-zerotier Module

Status: `done`

Suggested branch: `feat/router-zerotier-module`

## Goal

Add a `router-zerotier` module following the same overlay VPN pattern as
`router-tailscale` and `router-netbird`.

## Background

ZeroTier is a software-defined networking overlay that predates WireGuard. It
uses its own protocol (not WireGuard-based) and dynamic interface naming:
interfaces are named `ztXXXXXXXX` where the suffix is the 10-digit network ID.
The upstream NixOS module is `services.zerotierone`.

ZeroTier is popular in homelab contexts as an alternative to Tailscale/Netbird,
particularly because it supports self-hosted controllers via ZeroTier Central
or the open-source `ztncui` / `ZeroTierOne` controller.

## Scope

- Create `modules/router-zerotier.nix`
- Wrap `services.zerotierone` with router-firewall integration
- Register in `flake.nix` under `nixosModules.default` and as a named module
- Add `docs/router-zerotier.md`
- Update `docs/overlay-vpn.md` table to include ZeroTier

## Key design decisions

**Interface naming**: ZeroTier interface names include the network ID
(`zt<networkId>`), which is only known at runtime. The module should accept an
`interfaceName` option with no glob-style default. When `trustedInterface =
true`, require `interfaceName` with a clear assertion because the
router-firewall `overlayInterfaces` option takes exact interface names.

**Port**: ZeroTier listens on UDP 9993 by default.

**Routing**: `services.zerotierone` in nixpkgs does not have a
`useRoutingFeatures` equivalent — IP forwarding must be enabled explicitly via
`boot.kernel.sysctl`. The module should do this when `useRoutingFeatures` is
set to `"server"` or `"both"`.

**Networks**: `services.zerotierone.joinNetworks` accepts a list of network IDs.
The module should expose this as a convenience option.

## Minimum Options

- `enable`
- `interfaceName` — must be set explicitly (no safe default); consider an
  assertion requiring it when `trustedInterface = true`
- `joinNetworks` — list of ZeroTier network IDs to join
- `port` — default 9993
- `useRoutingFeatures` — default `"server"` for router use
- `trustedInterface` — default `true`
- `openFirewall` — default `true`
- `secretFile` — optional path to ZeroTier identity secret for persistent node ID

## Validation

- Evaluates cleanly with and without `router-firewall`
- Port conflict assertion when zerotier and netbird share a port (unlikely but
  possible if ports are overridden)
- `docs/router-zerotier.md` matches the style of `docs/router-netbird.md`
