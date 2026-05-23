# 57 - Router CLAT Elixir Control-Plane Path and Selector

## Status: `done`

## Objective

Introduce an Elixir `router-clat` control-plane path behind an explicit
selection boundary so the project can prove parity without silently replacing
the current Python control plane.

## Rationale

Round 126 supported Elixir as a plausible fit for the mature control-plane
problem, but did not converge on immediate repo extraction.

The common safe ground was:

- make the control-plane contract backend-neutral
- prove preserved behavior
- and keep the rollout explicit

This item exists to make the Elixir path real without pretending the migration
decision is already complete.

## Requirements

- [x] Add an explicit control-plane selection surface for `router-clat`, such as
      a module option that can distinguish the current Python path from a new
      Elixir path
- [x] Keep the control-plane input/output contract backend-neutral rather than
      encoding Tayga config details as the public API
- [x] Implement the first bounded Elixir path against the frozen control-plane
      contract, including:
      - mapping state
      - TTL / GC
      - artifact generation
      - reload/apply orchestration
      - status surface
- [x] Ensure unsupported or partial parity states are surfaced honestly rather
      than defaulting silently to the new path

## Verification

- [x] A contributor can run the Python or Elixir control-plane path
      intentionally rather than by accidental packaging drift
- [x] The Elixir path consumes and emits the declared contract surfaces
- [x] The resulting module boundary remains explicit about experimental / parity
      state if the new path is not yet the default

## Notes

This item is not the repo-extraction decision itself.

The goal is to make the Elixir path evaluable and testable under the existing
module boundary first.
