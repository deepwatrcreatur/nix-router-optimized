# 80 - Router Translation Backend Shared Adapter Surface

## Status: `ready`

## Objective

Turn the translation-backend boundary documented in
[`router-translation-backends.md`](../router-translation-backends.md) into a
real repo-internal adapter surface that `router-nat64` and `router-clat` can
share, while keeping Tayga as the only supported backend.

Suggested branch: `feat/router-translation-backend-surface`

## Rationale

Item `63` made the NAT64 / CLAT backend contract explicit, but the actual module
surface is still Tayga-shaped:

- `router-nat64` directly wires `services.tayga`
- current firewall/runtime assumptions still name the `nat64` interface
- `router-clat` and `router-nat64` do not yet share a typed internal adapter

That is acceptable for a single supported backend, but it leaves two concrete
gaps:

- there is no shared place to express “translation backend semantics” in code
- a future Jool experiment would otherwise have to punch through Tayga-specific
  assumptions ad hoc

This item exists to make the shared backend surface real **without** pretending
that a second backend is already supported.

## Requirements

- [ ] Introduce a repo-internal translation-backend adapter surface that can be
      used by both `router-nat64` and `router-clat`
- [ ] Keep Tayga as the only supported backend after this PR
- [ ] Make firewall/runtime assumptions explicit through the adapter surface
      instead of scattering Tayga-specific strings through consumer modules
- [ ] Separate:
      - public module options that remain stable
      - backend-specific rendered/runtime details that stay internal
- [ ] Preserve current supported behavior for the Tayga-backed path
- [ ] Update docs so contributors know this is an internal adapter boundary, not
      a promise of multi-backend support today

## Verification

- [ ] `router-nat64` still evaluates and behaves as the current supported Tayga
      path
- [ ] `router-clat` still evaluates against the same public contract
- [ ] The shared adapter surface is visible in code and understandable without
      reading Tayga-specific implementation first
- [ ] No new backend is implied as supported by default

## Notes

This item is about **creating the internal adapter boundary**.

It should not widen support claims beyond:

- Tayga is still the current supported backend
- the repo is now structurally prepared for an explicit experimental second
  backend later
