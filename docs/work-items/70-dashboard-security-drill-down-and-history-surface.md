# 70 - Dashboard Security Drill-Down and History Surface

## Status: `done`

## Objective

Extend the dashboard's firewall/security area beyond the current bounded
counter/detail slice if operators need deeper troubleshooting visibility.

The goal is a clearer operational surface for recent security activity, not a
write-capable firewall editor.

## Rationale

Item `64` delivered the first serious firewall drill-down:

- bounded chain and rule counters
- configured flowtable detail
- hot-chain and hot-rule summaries

But the repo still records a remaining gap in
`docs/IMPLEMENTATION-STATUS.md`:

- broader security/firewall drill-down beyond the bounded first counter/detail
  slice, if operators need more than top-chain and top-rule summaries

This item exists to turn that vague future work into a concrete next slice.

## Requirements

- [x] Identify the strongest next security/firewall visibility gaps after item
      `64`, such as:
      - recent trend/history rather than instantaneous counters
      - stronger correlation between logs, counters, and fail2ban state
      - more specific flow offload/runtime effectiveness cues
- [x] Pick a bounded read-only implementation surface rather than a broad
      kitchen-sink security page
- [x] Keep runtime collection lightweight enough for router hardware
- [x] Add API/UI contract coverage for the chosen slice
- [x] Update implementation-status wording so the remaining boundary is honest

## Verification

- [x] Operators can answer at least one meaningful security-troubleshooting
      question from the dashboard that still requires CLI today
- [x] The new surface remains read-only and bounded
- [x] Docs describe what is now visible versus what still requires raw CLI

## Notes

This item is about **security observability depth**, not firewall policy
mutation or a SIEM-style redesign.
