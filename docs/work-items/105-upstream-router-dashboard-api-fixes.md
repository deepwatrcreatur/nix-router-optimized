# Work Item 105: Upstream Router Dashboard API Hardening & Snapshot Handlers

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-19  

## Description

Port the dashboard backend fixes from downstream `scripts/router-dashboard-api-wrapper.py` directly into `modules/router-dashboard/api/server.py` and `modules/router-dashboard.nix`, deprecating the downstream monkeypatch wrapper.

## Context & Rationale

Downstream deployments found multiple issues in the upstream dashboard backend:
1. **Interface operstate and sysfs parsing:** Missing interfaces or malformed integer values in `/sys/class/net` caused crashes or blank network cards.
2. **Kea Lease Parsing:** Upstream backend lacked robust parsing for Kea's memfile CSV format (`dhcp4.leases`), including header validation, lease calculation, and active vs expired status.
3. **Unprivileged Fail2ban Inspection:** The unprivileged dashboard process cannot connect directly to `/run/fail2ban/fail2ban.sock`. Downstream introduced a periodic timer snapshotting fail2ban jail state to `/run/router-dashboard/fail2ban-status.json` with read-only dashboard permissions.
4. **Caddy ACME Diagnostics:** Dashboard Caddy handler lacked access to Cloudflare credentials to verify live DNS challenge state.

To work around these in production, downstream authored a 497-line python script monkeypatching 5 methods on `module.RouterAPIHandler` at runtime.

## Objectives

1. Merge the improved parsing logic from `router-dashboard-api-wrapper.py` directly into `modules/router-dashboard/api/server.py`:
   - Robust `/sys/class/net` interface statistics collection.
   - Native Kea DHCP4 CSV parsing.
   - Snapshot-based fail2ban status reading.
   - Secret-backed Caddy verification.
2. In `modules/router-dashboard.nix`, provide built-in snapshot services/timers for fail2ban and Kea leases so external processes are polled securely without escalating dashboard daemon privileges.

## Acceptance Criteria

- [ ] Upstream `server.py` natively supports all 5 hardened handlers.
- [ ] Downstream wrapper script is rendered obsolete.
