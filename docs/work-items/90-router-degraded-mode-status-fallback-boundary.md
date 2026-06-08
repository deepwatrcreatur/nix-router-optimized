# 90 - Router Degraded-Mode Status Fallback Boundary

## Status: `ready`

## Objective

Decide whether `nix-router-optimized` should add a deliberately minimal
degraded-mode status surface in addition to the richer dashboard and
`router-diag`, and if so, what narrow boundary would make it worth supporting.

Suggested branch: `docs/router-degraded-mode-status-boundary`

## Rationale

Discussion 16 did **not** recommend copying the OpenBSD router's static status
page as a replacement for the dashboard.

It did raise one narrower question:

- is there value in a very low-dependency fallback status surface when the richer
  dashboard or its supporting services are degraded?

This is lower priority than the runbook and safety work, but it is worth
resolving explicitly so future agents do not oscillate between:

- "the dashboard is enough"
- and "we need a static page because OpenBSD had one"

## Requirements

- [ ] Evaluate the existing degraded-mode coverage from:
      - `router-diag`
      - the dashboard
      - and current service status/reporting paths
- [ ] Decide whether a new fallback surface is:
      - unnecessary
      - justified as a very narrow addition
      - or better expressed as improved `router-diag` guidance instead
- [ ] If a fallback is justified, define strict boundaries for:
      - transport / binding
      - attack surface
      - content scope
      - and interaction with the main dashboard
- [ ] Record the decision clearly so this question does not stay implicit

## Verification

- [ ] The repo has an explicit answer to whether degraded-mode status needs a new
      surface
- [ ] Any approved fallback remains clearly distinct from the main dashboard
- [ ] If the answer is "no new surface", the decision is still documented

## Notes

This item is intentionally lower priority than the operational safety and
validation work above it.
