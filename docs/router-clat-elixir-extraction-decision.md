# router-clat Elixir Extraction Decision

## Status

Decision date: `2026-05-22`

Decision: **do not extract the Elixir `router-clat` control plane into a
separate repo yet.**

## Why This Decision Exists

The repo now has:

- a frozen backend-neutral control-plane contract
- named preservation fixtures
- a bounded non-default Elixir preview path

That is enough to make the extraction decision explicit. It is **not** enough
to justify a split by inertia.

This note exists so contributors do not infer that:

- the Elixir path is already the preferred operator path
- a separate repo is inevitable
- or repo layout remains undecided simply because both Python and Elixir exist

## Current Decision

The Elixir control plane remains **in-repo** for the foreseeable near term.

The repo is intentionally choosing:

- one integration surface
- one queue
- one compatibility boundary
- and one place where preservation tests and NixOS wiring evolve together

The current Elixir path should be treated as:

- a bounded parity implementation
- explicitly opt-in via `services.router-clat.controlPlane.backend = "elixir-preview"`
- not the default operator path
- not yet a release boundary of its own

## Why Extraction Is Premature

Extraction would introduce real costs immediately:

- separate versioning and release management
- cross-repo compatibility mapping between contract version and package version
- extra packaging and Nix input maintenance
- split ownership for preservation and integration tests
- more ways for operators to end up on an unsupported matrix by accident

Those costs would be easier to justify if the Elixir path already had:

- broader preservation evidence than the current fixture/unit slice
- dedicated CLAT VM lifecycle coverage
- stronger operator/runtime incident experience
- a decision that the Elixir path is likely to become the default

Right now, none of those are true strongly enough.

## Evidence Threshold For Reconsidering Extraction

The repo should reconsider extraction only after all of the following are true:

1. The Elixir path has preservation parity beyond the current unit/fixture set.
2. Dedicated CLAT VM tests cover lifecycle, persistence, artifact presence, and
   degraded-health behavior.
3. The Elixir path has enough operator/runtime evidence that making it the
   default is a realistic next question.
4. The repo can describe a release boundary without guesswork.

## What The Release Boundary Would Need Later

If extraction is reconsidered later, the future split must define at least:

- versioning strategy
  - control-plane contract version vs implementation release version
- packaging boundary
  - what artifact is shipped and how Nix consumes it
- compatibility policy
  - which repo-side module versions are compatible with which control-plane
    releases
- test ownership
  - which tests stay in the extracted repo
  - which integration and NixOS tests stay here

That boundary is intentionally deferred until the evidence supports it.

## Practical Guidance For Contributors

For now:

- treat the Python and Elixir paths as two in-repo implementations of one
  contract
- evolve preservation tests here first
- keep the selector explicit and non-default
- do not introduce a second flake input or external release dependency for the
  Elixir path yet

## Related Notes

- [`docs/router-clat-control-plane-contract.md`](./router-clat-control-plane-contract.md)
- [`docs/router-clat-preservation-plan.md`](./router-clat-preservation-plan.md)
- [`docs/work-items/57-router-clat-elixir-control-plane-path-and-selector.md`](./work-items/57-router-clat-elixir-control-plane-path-and-selector.md)
