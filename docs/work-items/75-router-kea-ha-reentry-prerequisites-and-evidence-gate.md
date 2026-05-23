# 75 - Router Kea HA Re-entry Prerequisites and Evidence Gate

## Status: `done`

## Objective

Turn the current vague "retry HA later" stance into an explicit gate for when a
future two-node Kea HA retest is allowed, what must already be true before that
re-entry, and what live evidence must be captured before anyone claims renewed
HA convergence.

## Rationale

Fresh live evidence now shows:

- `router` is the active owner
- `router-backup` is intentionally management-only standby
- the latest live truth is no longer a mismatched active HA pair

That is a better and safer state than the earlier mixed deployment, but it also
means the repo still lacks a sharp answer to:

- when should operators stay in explicit single-owner standby
- when is it appropriate to deliberately reintroduce two-node Kea HA
- what evidence package is required before anyone says HA has converged

This item exists so future HA work starts from a clear gate instead of from
ambiguous incident debt or optimistic memory.

## Requirements

- [x] Define the supported near-term default explicitly:
      remain management-only / single-owner standby
- [x] If re-entry is allowed, document the prerequisites before any live retest:
      - backup service-plane connectivity is present and intentional
      - both nodes are deployed to the same LAN-plane HA transport model
      - `keepalived`, `kea-dhcp4-server`, and `kea-dhcp-ddns-server` ownership
        stance is deliberate on both nodes
      - rollback anchors are identified before mutation
- [x] Define the minimum live evidence package for any future HA-closure claim
- [x] Update incident/docs so operators can distinguish:
      - current single-owner standby truth
      - future HA re-entry prerequisites
      - closure-quality evidence requirements

## Verification

- [x] Operators can tell exactly what must be true before a new two-node Kea HA
      retest begins
- [x] Operators can tell exactly what commands/evidence are required before
      saying HA converged
- [x] The repo no longer relies on vague phrases like "retry later" without
      naming the gating conditions

## Outcome

The re-entry gate is now documented in
[`docs/router-kea-ha-reentry-gate.md`](../../docs/router-kea-ha-reentry-gate.md):

- five explicit prerequisites that must all be satisfied before any HA retest
- a six-part evidence package (A through F) required before any HA closure claim
- a decision matrix (stay vs re-enter) based on prerequisite and evidence state
- explicit listing of what does not count as evidence

## Notes

This item is about **re-entry discipline and evidence gates**, not about broad
router HA redesign.
