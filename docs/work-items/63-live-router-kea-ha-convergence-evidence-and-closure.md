# 63 - Live Router Kea HA Convergence Evidence and Closure

## Status: `done`

## Objective

Collect fresh repo-tracked live evidence for the actual router pair and use it
to replace stale “almost converged HA” framing with the honest current support
boundary.

## Rationale

Item `62` closed the source ambiguity:

- the repo now defines the supported Kea HA transport shape
- unsafe localhost and wildcard HA address forms are rejected
- eval coverage proves the intended LAN-plane self/peer URL rendering

What remained was an operations-backed evidence step. The older committed live
evidence still showed a mixed deployment, so the incident could not honestly
move forward until a fresh retest was committed.

That retest changed the picture again: the live pair is not running Kea HA at
all. This item therefore became an evidence-and-decision task rather than a
simple “prove HA convergence” closure step.

## Requirements

- [x] Capture fresh live evidence from both `router` and `router-backup`
- [x] Replace stale E43 “mixed HA transport” framing with the latest live
      reality
- [x] Decide whether the incident should remain an HA-restoration task or be
      reframed around the actual supported operating mode
- [x] Update the incident summary and ledger so operators can tell that Kea HA
      is not currently in service on this pair

## Verification

- [x] The incident summary no longer cites E43 as the latest known live state
      if closure is claimed
- [x] The repo contains the live commands/output summary needed to justify the
      new boundary
- [x] Operators can tell exactly when the live pair was last verified

## Notes

Outcome:

- fresh live evidence established that the pair is not running Kea HA at all
- the planning round concluded the honest current boundary is single-active
  DHCP with manual promotion, not implicit HA restoration
- the remaining work is now follow-up boundary/runbook cleanup, not continued
  incident-driven “HA convergence” pursuit

This was a live-environment evidence task, not another source-module refactor.
