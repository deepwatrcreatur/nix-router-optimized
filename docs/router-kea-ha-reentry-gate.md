# Kea HA Re-entry Prerequisites and Evidence Gate

This document defines the conditions under which it is appropriate to
re-introduce two-node Kea HA on the reference router pair, and the minimum
evidence package required before any future HA-closure claim.

## Current Supported Default

**Single-active DHCP with manual promotion.**

- `router` is the sole active DHCP node.
- `router-backup` is a management-only standby with Kea intentionally skipped.
- There is no automatic DHCP failover on the reference pair today.
- See [`router-dhcp-single-active.md`](./router-dhcp-single-active.md) for the
  current support boundary and promotion runbook.

Operators should remain on this default until every prerequisite in this
document is satisfied.

## Re-entry Prerequisites

All of the following must be true before any live Kea HA retest begins.

### 1. Service-plane connectivity is present and intentional on both nodes

- `router-backup` must have deliberate LAN-plane reachability, not just
  management access.
- Both nodes must be reachable on the HA control-plane transport addresses
  (the per-node LAN HA addresses, e.g. `10.10.10.2` / `10.10.10.3`).
- The backup node's LAN interface must not be suppressed by a carrier guard
  or link-down state that would prevent HA sync traffic.

### 2. Both nodes deploy the same Kea HA transport model

- The `router-kea` module's `dhcp4.ha` options must be identically shaped on
  both nodes: same hook libraries, same HA mode, same peer topology.
- Both nodes must include `libdhcp_ha.so` **and** `libdhcp_lease_cmds.so`.
- The `this-server-name`, `peerName`, `localAddress`, and `peerAddress` values
  must form a consistent pair.

### 3. Keepalived, Kea, and DDNS ownership stance is deliberate on both nodes

- The operator must decide whether Kea HA is expected to follow VRRP
  transitions or operate independently.
- If Kea HA runs alongside VRRP, the `keaSync` and BGP `singleActiveOwner`
  interactions must be reviewed for conflicts.
- `kea-dhcp-ddns-server` ownership (if DDNS is in use) must be explicitly
  decided: does DDNS follow the HA primary, or does each node run its own?

### 4. Rollback anchors are identified before mutation

- The current working NixOS generation on both nodes must be recorded.
- `nixos-rebuild test` (not `switch`) should be used for the initial HA
  deployment so rollback is a reboot away.
- The operator must know how to revert to single-active DHCP if HA does not
  converge.

### 5. No dormant HA config is assumed to be active

- Any existing Kea HA configuration blocks that were carried forward from
  earlier design iterations must be explicitly reviewed, not assumed correct.
- The `dhcp4.ha.enable` flag must be set deliberately, not inherited from
  stale config.

## Minimum Evidence Package for HA Closure

Before anyone claims that Kea HA has converged on the reference pair, **all**
of the following must be demonstrated with timestamped evidence.

### A. Both nodes show active HA state

```bash
# On each node:
systemctl status kea-dhcp4-server    # must be active
curl -s http://localhost:8000/ | jq . # or equivalent Kea control channel check
```

Both nodes must show Kea running with HA hooks loaded and the HA state must
be either `hot-standby` or `load-balancing` (not `waiting`, `syncing`, or
`terminated`).

### B. HA sync is functional

```bash
# On the primary:
echo '{"command": "ha-heartbeat"}' | socat - UNIX:/run/kea/kea4-ctrl-socket.sock
```

The heartbeat response must show the peer as reachable and in a known state.

### C. Fresh client leases work from the intended active node

- Connect a fresh client (or release/renew an existing one).
- Confirm a lease is issued.
- Confirm the lease server-id matches the expected active node.

### D. Failover actually works

- Simulate a primary failure (stop `kea-dhcp4-server` on the primary or
  disconnect its LAN interface).
- Confirm the secondary promotes and serves fresh leases.
- Confirm the lease pool is consistent (no duplicate assignments).

### E. Failback is clean

- Restore the primary.
- Confirm HA sync resumes without manual intervention.
- Confirm no lease conflicts or pool corruption.

### F. The evidence is recorded

All of the above must be captured in a timestamped evidence block (shell
output, not memory) and linked from the incident or work-item history.

## What Does NOT Count as Evidence

- "The config looks right" — config correctness is necessary but not sufficient.
- "It worked on a test VM" — the gate is about the reference pair, not a
  synthetic environment.
- "HA was working before the incident" — the incident proved that prior
  assumptions were wrong.
- Partial evidence (e.g. heartbeat works but failover was never tested).

## Decision: Stay or Re-enter

| If... | Then... |
|---|---|
| Any prerequisite is unmet | Stay on single-active. Do not proceed. |
| All prerequisites are met but evidence is incomplete | Stay on single-active. Collect remaining evidence. |
| All prerequisites are met and full evidence package is captured | HA re-entry is permitted. Update the support boundary docs. |

## Relationship to Existing Docs

- [`router-dhcp-single-active.md`](./router-dhcp-single-active.md) — current
  default boundary and promotion runbook
- [`incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md`](./incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md) — the incident that established this boundary
- [`DHCP_SELECTION.md`](./DHCP_SELECTION.md) — backend selection guide
  (router-kea vs router-dhcp vs router-technitium)
