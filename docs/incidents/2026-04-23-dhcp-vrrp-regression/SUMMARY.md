# Incident: DHCP / VRRP Regression

**Status:** RESOLVED
**Severity:** P1
**Opened:** 2026-04-23
**Resolved:** 2026-05-23
**IC:** shared / rotating
**Ops:** shared / rotating

## Problem Statement

During the HA/VRRP transition, fresh LAN clients stopped receiving DHCP leases.
The root symptom was not one bug but a stack of issues across Kea runtime
shape, HA control-plane reachability, missing HA hook support, and finally
deployment divergence between `router` and `router-backup`.

This incident is now resolved as an **explicit single-active DHCP boundary**:
fresh live evidence and current source state agree that the pair is not running
Kea HA at all, `router` is the active DHCP node, and `router-backup` is
currently a manual promotion target rather than an automatic DHCP failover
peer.

## Confirmed Facts

1. The old `server-id` startup crash was a generation-specific artifact, not a
   property of the current source state. Source: E37.
2. Kea in the current "third-state" runtime can receive fresh DHCP broadcasts;
   the earlier outage was masked by HA state, not just socket shape. Source:
   E34, E35, E36.
3. `nix-router-optimized` had a real localhost self-URL regression in HA URL
   rendering. Source: E37.
4. Kea HA sync also required `libdhcp_lease_cmds.so`; HA was not operational
   with `libdhcp_ha.so` alone. Source: E38.
5. The staged production design uses per-node LAN HA addresses
   (`10.10.10.2`, `10.10.10.3`) and a backup-only carrier guard. Source: E39,
   E40, E41.
6. The current live pair is not running Kea HA at all. Fresh 2026-05-22 live
   evidence shows `router` serving DHCP successfully from `10.10.10.2`, but
   its live DHCP4 config exposes no HA hook library or HA control commands,
   while `router-backup` has the same non-HA config shape and its
   `kea-dhcp4-server` unit is intentionally skipped by `ExecCondition=exit 1`.
   Source: E42, E44.
7. The project has now made an explicit design decision not to treat active
   Kea HA restoration as the default next move for this pair. The honest
   current support boundary is single-active DHCP with manual promotion of
   `router-backup` if needed. Source: E45.

## Closing Decision

- [x] The stale “HA convergence” framing is retired.
- [x] The current live and source-of-truth picture is now explicit:
  `router` is the sole active DHCP node and `router-backup` is a manual
  promotion target.
- [x] Any future Kea HA revival is deferred to a fresh design stream with a
  stricter proof bar on this actual pair rather than being treated as the
  expected closure path for this incident.

## Ruled-Out Hypotheses

- ~~**H6:** Kea 3.x in the current third-state runtime cannot receive fresh
  DHCP broadcasts.~~ Disproven by E34 and E36.
- ~~**H7:** The only remaining issue is missing software support in Kea HA.~~
  Disproven by E39 through E43; software blockers were cleared, then rollout
  state and topology became the active boundary.
- ~~**H9:** The incident must remain open until the live pair is restored to
  active Kea HA.~~ Retired by E44 and E45; the current support boundary is
  explicit single-active DHCP, not “nearly restored” HA.

## Timeline

| Time | Event |
| --- | --- |
| 2026-04-23 | Incident opened after HA/VRRP rollout broke fresh-client DHCP |
| 2026-04-24 | Third-state runtime proved capable of serving fresh clients once HA left `READY` |
| 2026-04-24 | HA localhost self-URL regression identified and patched |
| 2026-04-24 | Missing `libdhcp_lease_cmds.so` requirement identified and patched |
| 2026-04-24 | LAN-plane HA design and backup carrier guard staged and built |
| 2026-04-24 | Live evidence showed `router` and `router-backup` still running different HA transports |
| 2026-05-22 | Fresh live evidence showed `router` serving DHCP without any active Kea HA hook/config, while `router-backup` skipped Kea entirely via `ExecCondition` |
| 2026-05-23 | A real multi-seat planning round concluded that the honest current boundary is single-active DHCP with manual promotion, not active Kea HA restoration |

## Residual Follow-Ups

- [ ] Make the manual promotion boundary and runbook explicit in the router docs
      and support surface.
- [ ] Decide whether the dormant Kea HA configuration should be removed
      entirely from the live design path or preserved only behind a clearly
      deferred future-design boundary.
- [ ] Keep any future Kea HA work in a new design/revalidation stream rather
      than reopening this incident implicitly.

## Change Control

- **Current mode:** live probe allowed / targeted deployment allowed
- **Mutation owner:** not currently assigned
- **Rollback anchor:** existing router generations and `nixos-rebuild test`
  workflow on each node
- **Success signal:** the repo and incident history consistently describe
  single-active DHCP on `router`, manual promotion of `router-backup`, and no
  false claim that Kea HA is currently in service
- **Failure signal:** the docs drift back into implying active or nearly-active
  Kea HA without a fresh design/proof stream, or live DHCP on the intended
  active node regresses again

## Next Action

**Who:** Router follow-up owner
**What:** Carry the manual-promotion / non-HA boundary into the remaining
router docs and runbook surface.
**Method:** complete the follow-up work item that standardizes `router-backup`
as a promotion target and decides how the dormant HA config is preserved or
removed.

## Navigation

- [Research Ledger](./RESEARCH_LEDGER.md)
- [Active Discussion](./ACTIVE_DISCUSSION.md)
