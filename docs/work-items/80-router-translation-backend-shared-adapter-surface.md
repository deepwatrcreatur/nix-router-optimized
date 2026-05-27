# 80. Router Translation Backend Shared Adapter Surface

**Status:** done
**Priority:** high
**Depends on:** 63-router-nat64-backend-abstraction-and-jool-spike.md

## Why this exists

`router-nat64` and `router-clat` both currently depend on Tayga, but they still
spell that dependence in slightly different local ways:

- interface names are hardcoded separately
- firewall/runtime assumptions are duplicated
- Tayga config rendering is duplicated
- future backend work would have to unwind module-local assumptions before it
  could even be evaluated honestly

We already documented the public versus Tayga-specific boundary in
[`docs/router-translation-backends.md`](../router-translation-backends.md).
This item turns that documentation into a real shared internal adapter surface
without widening support claims.

## Required outcome

Create one shared internal translation-backend adapter layer that:

- is used by both `router-nat64` and `router-clat`
- preserves the current Tayga-backed runtime behavior
- keeps Tayga as the only supported backend
- makes interface/firewall/runtime lifecycle assumptions explicit in one place
- separates stable module intent from backend-specific implementation details

## Scope

In scope:

- introduce an internal helper / adapter surface for the current Tayga backend
- route `router-nat64` through that adapter
- route `router-clat` through that adapter
- preserve current interface names and behavior unless a testable reason
  requires adjustment
- update docs so contributors understand that this is internal backend shaping,
  not “Jool support landed”

Out of scope:

- adding a public user-facing backend selector
- claiming backend parity
- changing the default backend away from Tayga
- landing Jool itself

## Acceptance criteria

- `router-nat64` and `router-clat` share one internal translation backend
  surface
- current tests still pass for the Tayga-backed path
- the public module boundary stays narrow and honest
- docs explicitly say the repo still supports only Tayga at this stage
- follow-on Jool work can target the shared internal adapter instead of
  punching through per-module assumptions

## Notes

This is the implementation counterpart to the repo's backend-boundary docs.
It should make future backend experimentation smaller, but it must not turn
“internal adapter” into “promised multi-backend support.”
