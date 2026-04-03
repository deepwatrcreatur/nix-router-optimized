# 01 Router DDNS Module Inadyn

Status: `ready`

Suggested branch: `feat/router-ddns-inadyn`

## Goal

Add an optional `router-ddns` module backed by `inadyn`, keeping the module
thin and router-oriented.

This should be treated as derivative work from the existing Cloudflare DDNS
behavior in `unified-nix-configuration`, which currently lives in the router's
Caddy configuration rather than as a reusable flake module.

## Scope

- inspect the current Cloudflare DDNS path in `unified-nix-configuration`
  first, especially:
  - `hosts/nixos/router/caddy.nix`
  - `lib/hosts.nix` (`router.ddnsServices`)
  - router Cloudflare token secret wiring
- evaluate existing NixOS/inadyn packaging and service wiring
- add a `services.router-ddns` module layer
- support token-file based secret handling
- keep the backend choice fixed to `inadyn` in the first version

## Non-Goals

- supporting both `inadyn` and `ddclient` initially
- implementing provider HTTP logic by hand
- mixing DDNS with local resolver ownership

## Validation

- module evaluates cleanly when disabled and enabled
- service wiring is explicit and understandable to downstream consumers
- the proposed module clearly accounts for the existing Cloudflare/Caddy-based
  DDNS behavior so migration/extraction is plausible
