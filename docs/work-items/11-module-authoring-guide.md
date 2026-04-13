# 11 Module Authoring Guide

Status: `ready`

Suggested branch: `docs/module-authoring-guide`

## Goal

Write a `CONTRIBUTING.md` (or `docs/module-authoring.md`) that explains how to
add a new NixOS module to this flake. This lowers the barrier for community
contributions and captures the conventions that are currently implicit in the
existing modules.

## Why This Matters

The flake has developed clear conventions — the `hasRouterOption` guard,
`overlayInterfaces` registration, the opportunistic router-firewall pattern,
`mkDefault` for upstream settings — but they live only in code. A contributor
adding a new module today has to reverse-engineer the conventions from
`router-tailscale.nix` or `router-openvpn.nix`.

## Scope

Write a guide covering:

### Module anatomy

- Module file location: `modules/router-<name>.nix`
- Required inputs: `config`, `lib`, `options`, `...`
- `cfg = config.services.router-<name>` pattern
- `hasRouterOption` for optional inter-module integration
- `mkDefault` when overriding upstream service settings

### The router-firewall integration contract

- When to use `overlayInterfaces` vs `extraTrustedInterfaces` vs
  `extraForwardRules`
- Why `mkIf (hasRouterOption [...] && firewallEnabled)` instead of a bare
  `mkIf cfg.trustedInterface`
- The opportunistic pattern: modules work without router-firewall imported

### Overlay VPN modules specifically

- Point to `overlay-vpn.md` for the overlay pattern
- Port conflict assertions: when and how to write them
- `dnsResolverAddress` pattern for stable DNS forwarder targets

### Flake registration

- Add to `nixosModules.<name>`
- Add to `nixosModules.default` imports
- Add to example nixosConfigurations if the module needs a realistic test
  (or note that it belongs in the test suite instead)

### Documentation requirements per module

- `docs/router-<name>.md` with: summary, example, options table, interaction
  notes
- Work item in `docs/work-items/` for smoke tests
- Entry in `docs/work-items/README.md` queue

### Testing

- Where tests live (`tests/`)
- How to add an eval-only smoke test
- The `checks` output in flake.nix

## Validation

- The guide accurately describes all existing modules
- A new contributor following the guide can produce a module that evaluates
  cleanly on first try
- No conventions are described that contradict existing module code
