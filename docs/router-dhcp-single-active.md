# Router DHCP Single-Active Boundary

This note records the current support boundary for the **reference router
pair** discussed throughout the repo incident and planning history:

- `router` is the active DHCP node
- `router-backup` is a manual promotion target
- Kea HA is **not currently in service** on this pair

This is an operator-facing boundary note, not a claim that Kea HA can never be
supported in the repo. The module surface still contains HA primitives. What is
not supported today is pretending that the reference pair already has automatic
DHCP failover when the live evidence and current source state say otherwise.

## What This Means

For the current pair:

- fresh-client DHCP is expected to come from `router`
- `router-backup` is expected to stay in a standby-suppressed posture until it
  is intentionally promoted
- operators should not assume that DHCP service follows VRRP or WAN failover
  automatically

The safe mental model is:

- **WAN HA:** supported as its own bounded feature
- **DHCP on the reference pair:** single-active, manual promotion
- **Any future active Kea HA revival:** new design stream, new proof bar

## What Happens If `router` Dies?

There is currently **no promise of automatic DHCP failover** for this pair.

The recovery path is:

1. confirm that the primary `router` is actually unavailable or no longer the
   intended DHCP owner
2. keep or restore management access to `router-backup`
3. make sure `router-backup` has the intended service-plane/LAN reachability
4. promote `router-backup` in the consumer configuration so standby suppression
   is removed and DHCP ownership moves to the backup
5. deploy the promoted configuration
6. verify that:
   - Kea is active on the promoted node
   - fresh clients receive leases
   - any coupled DNS/DDNS/NTP behavior still matches the intended support
     surface

This is a **manual promotion** workflow, not transparent failover.

## Bounded Promotion Runbook

The exact switch lives in the consumer repo, not in `nix-router-optimized`
itself, so this runbook stays intentionally bounded.

### 1. Stabilize access

- reach `router-backup` over its management path first
- do not assume LAN-plane routing or VIP ownership is already correct

### 2. Confirm standby reality

Before promotion, the expected standby shape is:

- `router-backup` may skip `kea-dhcp4-server` entirely
- DHCP HA commands/hooks may be absent
- the box may be carrying management/recovery identity rather than active DHCP
  identity

That is normal for the current boundary.

### 3. Promote in the consumer config

In the consumer repo:

- flip the host-specific ownership/promotion switch that makes
  `router-backup` the active DHCP owner
- remove any standby-only service suppression that intentionally prevents Kea
  from starting
- do **not** rely on dormant Kea HA config alone to make this automatic

### 4. Deploy and verify

After promotion:

- Kea should be active on `router-backup`
- fresh clients should receive leases
- if your deployment couples DHCP to DDNS or NTP advertisement, verify those
  surfaces too

Recommended checks:

- service state: `systemctl status kea-dhcp4-server`
- fresh lease behavior from a new client
- any router-local DNS/DDNS sync status relevant to the deployment

### 5. Fail back intentionally

When the original primary returns, do not assume the system should silently
revert. Treat failback as another explicit ownership decision with the same
kind of verification.

## Dormant HA Config Policy

The repo may still contain Kea HA-oriented knobs and history because they are
useful for future design exploration. But for the reference pair, those knobs
must be treated as:

- **deferred future-design hooks**
- not present-tense support claims
- not evidence that automatic DHCP failover is currently in service

If consumer configs keep dormant HA blocks around, the surrounding docs and
comments should say so explicitly.

## Relationship To The Incident

Incident `2026-04-23` is resolved on this boundary:

- the stale “nearly converged Kea HA” framing is retired
- the current support story is honest
- the remaining work is support-boundary and promotion-runbook clarity, not
  pretending the pair already has active DHCP HA

When deploying a promotion-related change on this pair, pair that workflow with
[`router-apply-safety.md`](./router-apply-safety.md) so rollback and
post-switch validation are prepared before the change goes live.
