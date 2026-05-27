# 62 - Router Kea HA Transport Convergence and Incident Closure

## Status: `done`

## Objective

Resolve the repo-tracked DHCP/VRRP incident by making the Kea HA transport and
deployment boundary explicit, converged, and evidenced rather than leaving the
incident active with mixed live HA transports.

The bounded goal is to close the gap between:

- the intended LAN-plane HA design
- and the last recorded live mixed deployment state

with repo-tracked evidence suitable for incident closure.

## Rationale

The incident record shows that major software blockers were cleared, but the
latest committed evidence still says the live pair was not on a verified common
HA transport.

That leaves a real operational backlog item:

- the source tree and docs evolved
- but the incident remains active
- and the repo lacks committed evidence that both routers converged on the same
  supported HA transport and coherent HA behavior

This item exists so the incident does not linger as an undocumented “probably
fine now” state.

## Requirements

- [x] Converge the intended Kea HA transport/deployment shape for `router` and
      `router-backup` so both nodes use the same supported HA transport model
- [x] Capture repo-tracked evidence for the converged state, including at least:
      - matching HA URLs / transport expectations
      - listener/control-plane reachability
      - coherent HA state on both nodes
      - no fresh-client DHCP regression
- [x] Update the repo-tracked incident record with the evidence needed to move
      from `ACTIVE` to a justified closed/resolved state, if the convergence is
      successful
- [x] If convergence fails, record the remaining boundary clearly enough that it
      becomes a narrower follow-up rather than an ambiguous lingering incident

## Verification

- [x] The repo no longer records a mixed live HA transport as the latest known
      state if the issue has been resolved
- [x] Incident closure, if claimed, is backed by committed evidence rather than
      out-of-band workspace notes
- [x] Operators can tell from the repo what the supported Kea HA transport shape
      actually is

## Notes

This item is about **transport convergence and incident-record correctness**.

It should not expand into:

- generic Kea HA feature expansion unrelated to the incident
- broad router-HA redesign
- or replacing repo-tracked evidence with informal local notes

## Outcome

- This work item is now stale relative to the repo-tracked incident record in
  [`docs/incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md`](../incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md),
  which marks the incident **RESOLVED** as of 2026-05-23.
- The closure did **not** come from restoring active Kea HA on the live pair.
  It came from making the honest supported boundary explicit:
  - `router` is the active DHCP node
  - `router-backup` is a manual promotion target
  - active Kea HA restoration is deferred to a fresh design stream with a
    stricter proof bar
- The old “transport convergence” framing is therefore retired rather than kept
  as an apparently open queue item.
- Current source-of-truth follow-up documents are:
  - [`router-dhcp-single-active.md`](../router-dhcp-single-active.md)
  - [`router-kea-ha-reentry-gate.md`](../router-kea-ha-reentry-gate.md)
