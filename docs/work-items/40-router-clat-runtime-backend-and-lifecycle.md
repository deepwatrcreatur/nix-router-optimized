# 40 - Router CLAT Runtime Backend and Lifecycle

## Status: `in-progress`

## Objective

Turn `router-clat` from a contract-only declarative slice into a bounded
runtime-capable feature by adding explicit backend/runtime ownership:

- translation backend selection for the first slice
- `clat0` interface lifecycle
- systemd/runtime ownership
- generated runtime artifacts

This item is about making the first slice **actually runnable** without
collapsing back into an opaque upstream wrapper model.

## Rationale

The current state of `router-clat` is materially better than a thin wrapper:

- option surface exists
- topology and coexistence assertions exist
- firewall/sysctl ownership exists
- experimental boundary language is visible

But the module still lacks the runtime middle:

- no backend instance
- no owned translation interface lifecycle
- no declared runtime unit graph
- no rendered runtime artifact path

Discussion 10 concluded that cleanup/surfacing was the right immediate follow-up,
and that the next substantial step should be a separate runtime-oriented item
rather than letting "contract-only" silently imply "feature complete."

## Requirements

- [x] Choose and document the first bounded runtime backend for `router-clat`
      without treating it as the long-term architecture by default
- [x] Make `router-clat` own the lifecycle of the translation interface
      (`clat0` or equivalent) declaratively
- [x] Add explicit systemd/runtime ownership for the first slice so the module
      no longer depends on an imagined external daemon or manually-created
      interface
- [x] Render deterministic runtime/backend artifacts from the module surface
      instead of burying runtime assumptions inside ad hoc scripts
- [x] Keep the current single-owner / non-HA boundary explicit and fail loudly
      on unsupported topology or ownership combinations
- [x] Preserve clean coexistence boundaries with at least:
      - `router-firewall`
      - `router-nat64`
      - host routing/sysctl ownership

## Verification

- [x] Enabling `services.router-clat.enable = true;` now results in a concrete
      runtime unit graph rather than only eval-time assertions
- [x] The translation interface lifecycle is owned declaratively by the module
- [x] Runtime artifacts are inspectable and reproducible from config
- [x] Unsupported topologies or ownership conflicts fail clearly rather than
      degrading silently
- [x] The resulting slice remains honest about being bounded and non-HA

## Notes

This item is about runtime/backend ownership, not yet the full control-plane
story for:

- DNS synthesis
- mapping allocation / refresh / expiry semantics
- richer observability surfaces

Those belong to follow-on CLAT work after runtime ownership exists.
