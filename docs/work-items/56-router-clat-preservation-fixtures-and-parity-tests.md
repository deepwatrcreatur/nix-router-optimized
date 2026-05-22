# 56 - Router CLAT Preservation Fixtures and Parity Tests

## Status: `ready`

## Objective

Build the preservation-test suite that proves a future Elixir control-plane path
preserves the intended `router-clat` behavior rather than merely replacing the
current Python daemon with something novel.

## Rationale

Round 126 converged strongly that preservation testing is mandatory from day
one.

The project needs explicit evidence for behavior preservation across:

- DNS synthesis
- mapping persistence
- TTL / GC
- reload / reconcile behavior
- runtime status surfaces
- full NixOS integration

Without that evidence, a language rewrite or repo split would mostly trade known
behavior for faith.

## Requirements

- [ ] Add a preservation-test plan and initial fixtures covering at least:
      - DNS synthesis parity
      - persistence across restart
      - TTL / GC behavior
      - crash recovery and atomic state writes
      - reload / reconcile behavior
      - status / degraded-state reporting
- [ ] Create black-box comparison fixtures so the current Python path and a
      future Elixir path can be exercised against the same cases
- [ ] Add backend-isolation tests or a fake backend path proving the suite does
      not silently encode Tayga as the only legal architecture
- [ ] Add or extend NixOS VM tests for:
      - service start
      - `clat0` lifecycle
      - state persistence across restart
      - artifact presence and inspectability
      - sane operator-visible health

## Verification

- [ ] The project has a named set of preserved behaviors that can be checked
      against both implementations
- [ ] At least one parity path exists that can compare Python and future Elixir
      behavior using the same fixtures
- [ ] The test suite covers both pure control-plane semantics and whole-system
      integration behavior

## Notes

This item is intentionally about behavior preservation, not about declaring the
Elixir path preferred yet.
