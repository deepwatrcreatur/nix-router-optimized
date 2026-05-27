# 81. Router Jool Experimental Backend Spike

**Status:** ready
**Priority:** medium
**Depends on:** 80-router-translation-backend-shared-adapter-surface.md

## Why this exists

The repo now documents that Jool is a plausible future backend candidate, but
it is not yet a supported path. Before any backend-expansion claims are made, we
need a bounded experiment behind the shared adapter surface from item 80.

## Required outcome

Build a strictly experimental Jool backend spike that:

- stays behind an explicit experimental selector or adapter gate
- does not replace Tayga as the default
- does not widen support claims
- records where parity is real versus missing

## Scope

In scope:

- Jool packaging/integration spike
- explicit adapter path for evaluation only
- comparison of lifecycle/firewall/observability fit against Tayga
- docs that clearly label the path as experimental

Out of scope:

- defaulting to Jool
- claiming backend parity before evidence exists
- deleting Tayga-specific coverage

## Acceptance criteria

- experimental Jool path exists behind an explicit non-default gate
- Tayga remains the supported default
- documentation clearly states the spike boundary
- missing parity areas are recorded instead of implied away
