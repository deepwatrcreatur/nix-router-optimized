# 10 router-headscale Module

Status: `done`

Suggested branch: `feat/router-headscale-module`

## Goal

Add a `router-headscale` module that configures Headscale — the open-source,
self-hosted Tailscale coordination server — alongside or instead of the hosted
`login.tailscale.com` control plane.

## Background

Headscale re-implements the Tailscale coordination API so that a standard
Tailscale client can connect to a self-hosted server. Running Headscale on the
router means:

- no reliance on Tailscale Inc.'s infrastructure for device registration or
  key rotation
- the control plane and the VPN gateway are co-located
- ACLs and device policies are controlled entirely in-house

Headscale is already in nixpkgs as `services.headscale`.

## Scope

- Create `modules/router-headscale.nix`
- Wrap `services.headscale` with sensible router defaults
- Integrate with `caddy-reverse-proxy` or `router-firewall` for the HTTPS
  endpoint that Tailscale clients contact
- Optionally wire into `router-tailscale` so that `authKeyFile` can be
  generated from a Headscale pre-auth key via a oneshot service
- Register in `flake.nix`
- Add `docs/router-headscale.md`

## Key design decisions

**Relationship to router-tailscale**: The Tailscale client configured by
`router-tailscale` needs to point at the Headscale server URL instead of
`login.tailscale.com`. The module should expose a `controlServerUrl` option and
feed it into the client join path with `tailscale up --login-server` (for
example by appending to `router-tailscale.extraUpFlags` when that module is
enabled), not via `extraDaemonFlags` or environment.

**HTTPS**: Headscale requires HTTPS. The module should integrate with
`caddy-reverse-proxy` if enabled, or document the manual certificate approach.

**Separation of concerns**: `router-headscale` should be usable on a host that
does *not* also run `router-tailscale` (e.g., a dedicated control-plane host),
so the inter-module wiring must be optional.

## Minimum Options

- `enable`
- `domain` — the public hostname for the Headscale server
- `port` — internal listen port (default 8080, proxied via Caddy)
- `settings` — pass-through to `services.headscale.settings` for full control
- `openFirewall` — expose port directly on WAN when Caddy is not used
- `useCaddy` — wire into `caddy-reverse-proxy` automatically (default `true`
  when that module is enabled)

## Validation

- Evaluates cleanly standalone and alongside `router-tailscale`
- The Caddy integration block is conditional on `caddy-reverse-proxy` being
  imported (use `hasRouterOption` pattern)
- `docs/router-headscale.md` documents the full workflow: deploy Headscale,
  generate a pre-auth key, wire it into `router-tailscale.authKeyFile`
