# Incident: DHCP / VRRP Regression

**Status:** ACTIVE
**Severity:** P1
**Opened:** 2026-04-23
**IC:** shared / rotating
**Ops:** shared / rotating

## Problem Statement

During the HA/VRRP transition, fresh LAN clients stopped receiving DHCP leases.
The root symptom was not one bug but a stack of issues across Kea runtime
shape, HA control-plane reachability, missing HA hook support, and finally
deployment divergence between `router` and `router-backup`.

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
6. The current live pair is not yet in a verified common HA state. After the
   PCI move and cable changes, `router-backup` now has LAN carrier, but its
   live Kea config is still on management-plane HA URLs while `router` is
   targeting LAN-plane HA URLs. Source: E42, E43.

## Active Hypotheses

- [ ] **H8:** The remaining blocker is deployment mismatch, not another Kea
  defect. Owner: open. Probe: deploy `router-backup` to the same LAN-plane HA
  config as `router`, then inspect `config-get`, `ss`, and HA state on both
  nodes.

## Ruled-Out Hypotheses

- ~~**H6:** Kea 3.x in the current third-state runtime cannot receive fresh
  DHCP broadcasts.~~ Disproven by E34 and E36.
- ~~**H7:** The only remaining issue is missing software support in Kea HA.~~
  Disproven by E39 through E43; software blockers were cleared, then rollout
  state and topology became the active boundary.

## Timeline

| Time | Event |
| --- | --- |
| 2026-04-23 | Incident opened after HA/VRRP rollout broke fresh-client DHCP |
| 2026-04-24 | Third-state runtime proved capable of serving fresh clients once HA left `READY` |
| 2026-04-24 | HA localhost self-URL regression identified and patched |
| 2026-04-24 | Missing `libdhcp_lease_cmds.so` requirement identified and patched |
| 2026-04-24 | LAN-plane HA design and backup carrier guard staged and built |
| 2026-04-24 | Live evidence showed `router` and `router-backup` still running different HA transports |

## Current Blockers

- [ ] `router` and `router-backup` are not yet deployed to the same HA transport.
- [ ] Full HA restoration is unverified until both nodes converge over the same
  live LAN-plane configuration.
- [ ] Root workspace planning files are informative, but repo-tracked incident
  history must stay authoritative for committed state.

## Change Control

- **Current mode:** live probe allowed / targeted deployment allowed
- **Mutation owner:** not currently assigned
- **Rollback anchor:** existing router generations and `nixos-rebuild test`
  workflow on each node
- **Success signal:** both nodes expose matching LAN-plane HA URLs, heartbeat
  succeeds, and HA state is coherent on both nodes
- **Failure signal:** peer heartbeat refusal/timeout continues after matching
  deployment, or fresh-client DHCP regresses again

## Next Action

**Who:** Ops
**What:** Deploy `router-backup` to the current staged LAN-plane HA config and
re-check live HA state on both nodes.
**Method:** `nixos-rebuild test/switch` for `router-backup`, followed by
`config-get`, `list-commands`, `ss -ltnp '( sport = :8000 or sport = :67 )'`,
and Kea journal inspection on both routers.

## Navigation

- [Research Ledger](./RESEARCH_LEDGER.md)
- [Active Discussion](./ACTIVE_DISCUSSION.md)
