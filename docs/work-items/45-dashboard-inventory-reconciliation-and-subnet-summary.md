# 45 - Dashboard Inventory Reconciliation and Subnet Summary

## Status: `in-progress`

## Objective

Overlay simple runtime reconciliation and subnet-summary cues onto the
repo-native inventory browser so operators can quickly see declared-vs-live
state without promoting the dashboard into an editing authority.

## Rationale

Discussion 12 repeatedly converged that the highest operator value is not
generic IPAM CRUD, but a read-only answer to questions such as:

- what is declared here
- what is currently leased/live
- what only exists in DNS or runtime state
- where are obvious gaps or conflicts

The strongest phpIPAM idea worth borrowing is not its backend, but its compact
visual browsing cues such as subnet occupancy and status coloring.

## Requirements

- [ ] Add bounded reconciliation states or provenance flags such as:
      - declared
      - leased
      - dns-only
      - conflict
- [ ] Add a compact subnet summary or occupancy view suitable for the dashboard
      surface
- [ ] Keep reconciliation read-only and derived from existing declarative +
      runtime sources
- [ ] Make any status coloring or summary view legible without requiring
      `phpIPAM`-style application complexity

## Verification

- [ ] The inventory browser can distinguish intent from live runtime observations
- [ ] Operators can quickly identify subnets/hosts that deserve follow-up
- [ ] The resulting surface remains clearly non-authoritative and read-only

## Notes

This item should follow the data-contract and base-browser work.
It is the place to borrow phpIPAM-like browse **patterns** without importing
phpIPAM code or authority boundaries.
