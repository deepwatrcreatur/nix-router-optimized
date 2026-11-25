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
- Kea HA runs on both nodes regardless of VRRP role. `kea-dhcp4-server`
  must not be in `services.router-ha.singleActiveUnits`; evaluation fails if
  it is. The retired `services.router-ha.keaSync` option has no effect.
- The BGP `singleActiveOwner` interaction must be reviewed for conflicts.
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
echo '{"command": "ha-heartbeat"}' | socat - UNIX-CONNECT:/run/kea/dhcp4.sock | jq .
```

Both nodes must show Kea running with HA hooks loaded and the HA state must
be either `hot-standby` or `load-balancing` (not `waiting`, `syncing`, or
`terminated`).

### B. HA sync is functional

```bash
# On the primary: a lease handed out by the peer must be present here.
echo '{"command": "lease4-get", "arguments": {"ip-address": "<client ip>"}}' \
  | socat - UNIX-CONNECT:/run/kea/dhcp4.sock | jq .result   # 0 = found
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

## Simulated Evidence

The `vm-router-kea-ha` check (`tests/vm/router-kea-ha.nix`) runs evidence
items A–E against two VMs with the module defaults (load-balancing,
5 s heartbeat, 15 s `max-response-delay`, `max-unacked-clients` 0) and
`router-firewall` enabled:

| Step | Result in the VM |
|---|---|
| Both nodes reach `load-balancing` | about 10–30 s after boot |
| Fresh clients from 8 MACs | both servers answer a share; every lease appears on both nodes |
| HA port 8000 | reachable from the peer, refused to a LAN client |
| Primary's Kea stopped | secondary reaches `partner-down` about 13 s after the primary stops (the 15 s timer starts at the last answered heartbeat), then serves every client |
| Primary restarted | it pulls the leases it missed and both are back in `load-balancing` within about 10–20 s; no duplicate leases |

`vm-router-kea-ha-hot-standby` runs the same script with
`dhcp4.ha.mode = "hot-standby"`:

| Step | Result in the VM |
|---|---|
| Both nodes reach `hot-standby` | about 15 s after boot |
| Fresh clients from 8 MACs | only the primary answers; every lease appears on both nodes |
| Primary's Kea stopped | the standby reaches `partner-down` about 12 s later and serves every client |
| Primary restarted | it syncs the failover leases, both return to `hot-standby`, and renewing clients keep their addresses from the primary |

What clients notice when one node fails: clients that already have a lease
keep it and renew later, so they see nothing. A new or rebinding client whose
MAC hashes to the failed node gets no answer until the survivor reaches
`partner-down`, so up to about 20 s of DHCP retries. Tune this with
`dhcp4.ha.heartbeatDelaySec`, `maxResponseDelaySec` and
`maxUnackedClients` (raise the last when the HA link is a separate network
that can fail while the peer still serves clients).

Run it with `nix build .#checks.x86_64-linux.vm-router-kea-ha -L`.

Security: Kea 3.0's HA listener accepts lease updates without authentication
(it supports only TLS). `router-kea` therefore opens port 8000 to the
configured `peerAddress` only, through `router-firewall`. Without
`router-firewall`, restrict the port yourself.

This proves the module. It does not satisfy the gate for the reference pair;
see below.

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
