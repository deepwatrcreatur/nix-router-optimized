# 74 - Router DHCP Single-Active Boundary and Promotion Runbook

## Status: `done`

## Objective

Standardize the current router DHCP support boundary as:

- `router` is the active DHCP node
- `router-backup` is a manual promotion target
- Kea HA is not currently in service on this pair

and make that boundary operator-usable rather than only implicit in comments,
incident notes, or skipped systemd units.

## Rationale

Fresh live evidence and the Round 127 planning decision closed the ambiguity:
the project should not keep implying that this pair is “nearly restored” to
active Kea HA.

The honest current model is simpler:

- single-active DHCP on `router`
- standby suppression on `router-backup`
- manual promotion if the primary is lost

What is still missing is the operator-facing completion work:

- clear support-boundary docs
- a promotion/runbook path
- and a decision about whether dormant HA config should remain in the live
  design path at all

This item exists so that the repo’s day-to-day guidance matches the actual
operating mode and does not silently invite assumptions about automatic DHCP
failover that are false today.

## Requirements

- [x] Make the current DHCP support boundary explicit in the relevant router
      docs:
      - `router` is the active DHCP node
      - `router-backup` is a manual promotion target
      - Kea HA is not currently supported as an active service on this pair
- [x] Add or update a bounded promotion runbook for `router-backup`
- [x] Decide whether dormant Kea HA config should:
      - be removed from the live path entirely
      - or be preserved only behind an explicit future-design boundary
- [x] Remove or rewrite comments and notes that still imply the pair is
      expected to converge back to active Kea HA without a new design stream
- [x] Keep the resulting boundary consistent with the incident closure and the
      Round 127 decision

## Verification

- [x] An operator can answer “what happens if `router` dies?” from repo docs
      without guessing
- [x] The repo no longer implies automatic DHCP failover where none exists
- [x] Any preserved HA hooks/config are clearly marked as deferred future work
      rather than present-tense support
- [x] Incident `2026-04-23` and the standing router docs tell the same story

## Notes

This item is about **support-boundary cleanup and operator guidance**.

Outcome:

- the repo now has a dedicated
  [`router-dhcp-single-active.md`](../router-dhcp-single-active.md) note for
  the current router pair
- README and the DHCP server selection guide now stop implying automatic DHCP
  failover for the maintained reference pair
- the dormant HA path is explicitly described as deferred future-design surface
  rather than current support

It is not, by itself:

- a commitment to re-enable Kea HA
- a proof that automatic DHCP failover is supported
- or a substitute for a fresh HA redesign if that becomes a real product goal
