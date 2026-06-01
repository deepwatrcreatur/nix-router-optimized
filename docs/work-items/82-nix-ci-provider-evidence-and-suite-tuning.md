# 82. Nix CI Provider Evidence and Suite Tuning

**Status:** done
**Priority:** medium
**Depends on:** 78-coarse-ci-suites-and-local-check-boundary.md, 79-nix-ci-baseline-and-local-debugging-guidance.md

## Why this exists

The repo now has a cleaner coarse CI boundary and a fine-grained local check
surface, but we still do not have enough real provider-side evidence about how
`nix-ci.com` behaves with the current suite split.

We should not assume the present exported suite layout is optimal until we have
that evidence.

## Required outcome

Collect real provider-side CI evidence and decide whether the current suite
split is:

- appropriate as-is
- too granular
- too coarse
- or missing useful separation for failure diagnosis / cache reuse

## Scope

In scope:

- gather evidence from actual provider runs
- capture wall-clock behavior and failure-isolation behavior
- tune the suite grouping if needed
- update docs with the evidence and any resulting boundary changes

Out of scope:

- re-expanding the public CI surface back into many fine-grained leaves
- local-only opinions without provider evidence

## Acceptance criteria

- provider-side evidence is documented
- the suite split is either confirmed or adjusted
- docs explain the final public CI boundary and why it exists

## Outcome

- Added [`docs/router-nix-ci-baseline.md`](../router-nix-ci-baseline.md) as the
  durable provider-side record for the published mainline.
- Confirmed that published `github/main` at
  `f767a731984110699731a027377728cee12af4b1` still exposes the fine-grained
  public CI surface:
  - `178` `build checks.x86_64-linux.*` jobs
  - `2` package jobs
  - provider utility jobs (`configure`, `show x86_64-linux`)
  - `0` public `ci-*` suite jobs
- Confirmed that published `main` does not currently contain the coarse-suite
  implementation:
  - `tests/suites.nix` absent
  - `tests/fine-grained.nix` absent
  - `checksFineGrained` not exported from `flake.nix`
- Concluded that the current public CI boundary should be documented as
  fine-grained until the coarse-suite implementation is actually landed on the
  published branch.
