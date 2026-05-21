# 42 - Router CLAT Observability and Runtime Validation

## Status: `in-progress`

## Objective

Make `router-clat` inspectable, supportable, and testable once the runtime and
control-plane slices exist:

- runtime health/status surface
- logs and inspection paths
- dashboard or API visibility where appropriate
- validation beyond eval-time contract checks

This item exists so the feature does not stop at "configured and maybe running"
without giving operators a way to tell whether it is healthy or broken.

## Rationale

Discussion 10 identified a persistent risk even after the first-slice landing:

- the repo is good at making the feature honest on paper
- but there is still no operator-facing observability surface
- and no live/runtime-oriented validation beyond config/eval checks

Once runtime/backend ownership and DNS/mapping control-plane work land, the next
credible step is not feature sprawl but making the feature inspectable and
verifiable.

## Requirements

- [x] Expose a minimum runtime status surface for `router-clat`, such as:
      - configured vs active state
      - backend/runtime health
      - listener status
      - mapping counts or similar bounded summary
- [x] Define and implement the minimum useful logs / rejection reasons /
      inspection paths an operator needs when the first slice is unhealthy
- [x] Decide whether `router-dashboard` should surface CLAT status directly now
      or whether a narrower API/inspection path should exist first
- [x] Add validation that goes beyond pure eval, such as:
      - deterministic rendered-artifact tests
      - service start/dry-run checks
      - bounded VM or fixture-driven runtime validation
- [x] Make the non-HA and single-owner assumptions visible in the observability
      surface so operators do not infer guarantees that the module does not claim

## Verification

- [x] An operator can distinguish:
      - configured but inactive
      - active and healthy
      - active but degraded
      - unsupported topology / refusal state
- [x] The feature has at least one validation path stronger than config-shape
      eval alone
- [x] The observability surface does not overclaim maturity or HA behavior

## Notes

This item should follow the runtime/backend and control-plane work.

It is intentionally about:

- inspectability
- status
- bounded validation

not about opening new topology or HA scope.
