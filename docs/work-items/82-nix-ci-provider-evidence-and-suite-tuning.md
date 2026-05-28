# 82. Nix CI Provider Evidence and Suite Tuning

**Status:** ready
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
