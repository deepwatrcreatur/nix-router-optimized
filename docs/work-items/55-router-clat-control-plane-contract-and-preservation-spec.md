# 55 - Router CLAT Control-Plane Contract and Preservation Spec

## Status: `done`

## Objective

Freeze the backend-neutral `router-clat` control-plane contract and preserved
behavior before any Elixir reimplementation or repo split hardens accidental
runtime details into the product boundary.

## Rationale

Round 126 converged that the language question is secondary to the contract
question.

The project already has a meaningful `router-clat` runtime shape:

- DNS synthesis
- mapping allocation and persistence
- TTL / GC
- backend artifact generation
- reload sequencing
- runtime status/observability

If an Elixir path is introduced before those behaviors are frozen as the thing
to preserve, the repo risks arguing about repository layout while the actual
operator contract is still moving.

## Requirements

- [x] Write a dedicated contract note for the `router-clat` control plane that
      freezes the backend-neutral public boundary for at least:
      - desired-state input
      - durable mapping schema
      - artifact generation / apply-plan semantics
      - reload / restart expectations
      - runtime status / degraded-state reporting
      - backend adapter capabilities and failure semantics
- [x] Explicitly distinguish:
      - public control-plane contract
      - backend-specific Tayga adapter details
      - NixOS module integration details
- [x] Document the preserved external behaviors that any replacement
      implementation must match, including:
      - DNS synthesis classes and negative cases
      - mapping refresh / expiry semantics
      - restart persistence invariants
      - last-known-good / degraded-state behavior on apply failure
- [x] Make the boundary versionable enough that a later extracted control-plane
      repo could consume it without guessing

## Verification

- [x] A contributor can tell which `router-clat` behaviors are contractual versus
      incidental to the current Python implementation
- [x] The note is specific enough to drive preservation tests without depending
      on line-by-line Python behavior
- [x] Tayga remains clearly behind an adapter boundary rather than becoming the
      public architecture

## Notes

This item should land before any substantial Elixir implementation work or repo
split, even if the maintainer still prefers extraction soon after.
