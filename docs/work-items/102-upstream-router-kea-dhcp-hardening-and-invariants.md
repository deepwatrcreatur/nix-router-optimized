# Work Item 102: Upstream Kea DHCPv4 Hardening, Pool Exhaustion Protection, and Carrier Readiness

**Status:** ready  
**Priority:** P0 (Blocker)  
**Created:** 2026-09-19  

## Description

Upstream critical Kea DHCPv4 configuration options, pool exhaustion guards, expired lease reclamation, startup header validation, and LAN interface carrier-readiness gating from downstream production experience into `modules/router-kea.nix`.

## Context & Rationale

Downstream production routers encountered severe DHCP incidents leading to complete IP pool exhaustion and service startup failures:
1. **DUID Churn Pool Bloat:** Default Kea matching (`match-client-id = true`) allocates separate IP addresses when dual-booting, rebooting into PXE/installers, or cycling client identifiers. Setting `match-client-id = false` and `host-reservation-identifiers = [ "hw-address" ]` enforces strict physical MAC tracking.
2. **Prolonged Decline Lockouts:** Default Kea probation period for `DECLINED` leases is 86,400 seconds (24 hours). Devices encountering transient IP conflicts lock addresses out of the pool for a full day. Reducing `decline-probation-period` to 300 seconds allows swift recovery.
3. **Missing Lease Reclaimer:** By default, Kea in `memfile` mode does not aggressively reclaim or flush expired leases unless `expired-leases-processing` is explicitly configured with timers.
4. **Lease File Header Incompatibility on Upgrades:** Upgrading Kea packages can change CSV schema headers in `/var/lib/kea/dhcp4.leases`. Kea aborts on startup if the existing header does not match expected fields.
5. **Startup Carrier Race:** If `kea-dhcp4-server.service` starts before the physical LAN interface is `LOWER_UP` and has an IPv4 address assigned, raw socket binding fails or silently drops client discover packets.

## Objectives

1. Add options to `services.router-kea.dhcp4`:
   - `matchClientId` (bool, default `false`): Match strictly by MAC address to prevent DUID pool churn.
   - `declineProbationPeriodSec` (int, default `300`): Runtime probation time before declined leases can be reissued.
   - `expiredLeasesProcessing` (submodule with defaults: `reclaim-timer-wait-time = 10`, `flush-reclaimed-timer-wait-time = 25`, `hold-reclaimed-time = 300`, `max-reclaim-leases = 100`, `max-reclaim-time = 250`).
   - `hostReservationIdentifiers` (listOf str, default `[ "hw-address" ]`).
2. Add `systemd.services.kea-dhcp4-server.serviceConfig.ExecStartPre` scripts:
   - Header validation and declined lease sanitization (`ensureKeaLeaseState`).
   - Carrier and IP readiness guard waiting up to 30 seconds for the served LAN interface to be up (`waitForKeaLanReady`).

## Acceptance Criteria

- [ ] `services.router-kea` renders hardened defaults for client ID matching and decline probation.
- [ ] Expired leases are automatically reclaimed every 10–25 seconds.
- [ ] Daemon does not fail startup on boot when interface carrier initialization is delayed.
- [ ] Evaluation tests in `tests/router-kea-eval.nix` pass.
