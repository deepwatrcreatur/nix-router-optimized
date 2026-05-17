# 34 - Router BGP Auth, AFI, and Policy

## Status: `ready`

## Objective

Add the first serious production-oriented capability slice to `router-bgp`:
neighbor authentication, clearer address-family support, and a bounded route
policy surface.

## Rationale

Discussion 05 found that the current wrapper is too thin for anything beyond
trusted internal lab peering. The biggest capability gaps are authentication,
IPv6/address-family handling, and basic control over what routes are imported or
exported.

## Requirements

- [ ] Add per-neighbor authentication support that can consume secrets from
      runtime files rather than embedding credentials in the Nix store
- [ ] Add explicit address-family support for at least IPv4 and IPv6 unicast
- [ ] Add a bounded import/export policy surface suitable for common small-scale
      routing use without forcing raw FRR policy language everywhere
- [ ] Document the resulting configuration model
- [ ] Add focused eval coverage for the new option shapes

## Verification

- [ ] A user can configure authenticated BGP peering without storing secrets in
      the Nix store
- [ ] Dual-stack or explicit AFI routing is representable in module options
- [ ] Route import/export behavior is no longer all-or-nothing by default
- [ ] Docs and tests cover the new surface

## Notes

Keep this slice bounded. The goal is not to expose every FRR capability at once,
but to cover the most important missing guardrails for serious use.
