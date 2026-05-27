# 77 - Exported CI Check Surface Audit and Suite Plan

## Status: `done`

## Objective

Turn the current vague “too many exported checks” concern into a concrete map of
what `nix-router-optimized` exports today, which checks belong in the default CI
surface, and how that surface should collapse into a small number of meaningful
suites.

Suggested branch: `docs/router-ci-surface-audit`

## Rationale

Round 132 concluded that `nix-router-optimized` is the local outlier:

- `nix-router-optimized`: `174` exported `checks.x86_64-linux.*`
- `unified-nix-configuration`: `3`
- `agent-roundtable`: `1`

That does not automatically mean every fine-grained check is wrong.
It does mean the repo lacks a deliberate boundary between:

- checks that should stay CI-visible on every commit
- checks that are useful mainly for local debugging or targeted validation
- and checks that may be paying repeated eval/setup cost without enough public CI
  value

This item exists to make that boundary explicit before the flake outputs are
reshaped.

## Requirements

- [x] Inventory the currently exported `checks` surface by type, including at
      least:
      - `mkNixosEvalCheck`
      - `mkNixosEvalFailureCheck`
      - `runCommand` or other heavier checks
- [x] Group the current exports into a small number of logical families, such as:
      - positive eval coverage
      - negative/failure eval coverage
      - dashboard/UI invariants
      - heavier integration or runtime-style checks
- [x] Identify which leaves should remain directly exported and which should move
      behind coarser suite outputs
- [x] Propose a target exported shape in the `3`-to-`8` suite range
- [x] Call out any obvious duplicated evaluation or shared harness work that
      should be factored if the goal is real `nix-ci.com` worker-second savings
- [x] Document the proposed suite boundaries in repo docs so a follow-up
      implementation item can apply them without redoing the analysis

## Verification

- [x] A contributor can read one repo-local artifact and understand:
      - what the current exported surface is
      - what the proposed exported surface should become
      - why each family is CI-visible or local-only
- [x] The plan is specific enough that a follow-up implementation PR can reduce
      the exported surface without inventing a new categorization on the fly

## Notes

This item is about **mapping and deciding the exported CI boundary**.

It should not silently implement the new boundary as part of the same PR.

## Outcome

- Added [`docs/router-ci-check-surface-audit.md`](../router-ci-check-surface-audit.md)
  as the durable repo-local artifact for this decision.
- Captured the live exported surface as `174` leaves per supported Linux system.
- Mapped that surface into generated module-import coverage, doc/example checks,
  explicit positive evals, explicit negative boundaries, and runtime/unit-test
  leaves.
- Proposed a `6`-suite exported CI target for item `78`:
  - `ci-module-imports`
  - `ci-docs-and-examples`
  - `ci-router-positive-evals`
  - `ci-router-negative-boundaries`
  - `ci-dashboard-and-ui-contracts`
  - `ci-runtime-unit-tests`
- Recommended that fine-grained leaves remain available repo-locally for
  targeted debugging but stop being directly exported in the default CI surface.
