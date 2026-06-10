# 90 - Router Degraded-Mode Status Fallback Boundary

## Status: `done`

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

- [x] Evaluate the existing degraded-mode coverage from:
      - `router-diag`
      - the dashboard
      - and current service status/reporting paths
- [x] Decide whether a new fallback surface is:
      - unnecessary
      - justified as a very narrow addition
      - or better expressed as improved `router-diag` guidance instead
- [x] If a fallback is justified, define strict boundaries for:
      - transport / binding
      - attack surface
      - content scope
      - and interaction with the main dashboard
- [x] Record the decision clearly so this question does not stay implicit

## Verification

- [x] The repo has an explicit answer to whether degraded-mode status needs a new
      surface
- [x] Any approved fallback remains clearly distinct from the main dashboard
- [x] If the answer is "no new surface", the decision is still documented

## Outcome

Decision: no new fallback web/status surface for now.

The maintained degraded-mode boundary is:

- `router-dashboard` for the richer local HTTP surface
- `router-diag` for low-dependency read-only fallback status
- runbooks plus direct `systemctl`/`journalctl`/local `curl` checks when either
  richer surface is degraded

The question stays closed unless there is concrete evidence that `router-diag`
cannot cover a recurring degraded-mode status need without introducing another
dashboard-like listener.

## Notes

This item is intentionally lower priority than the operational safety and
validation work above it.
