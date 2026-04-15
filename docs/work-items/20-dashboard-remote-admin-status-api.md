# Dashboard Remote Admin Status API

Status: pending

Branch: `feat/dashboard-remote-admin-status-api`

## Goal

Expose a `/api/remote-admin/status` endpoint in the router dashboard API that summarizes configured remote administration entry points using declarative metadata from the router-remote-admin module.

## Scope

- Accept remote-admin metadata from the dashboard service environment (JSON), similar to `DASHBOARD_VPNS` and `DASHBOARD_TUNNELS`.
- Implement `/api/remote-admin/status` returning configured/active/warning/down counts and a list of entries with type, name, unit, URL, and status.
- Derive runtime health from systemd unit state and reachability hints without calling upstream provider APIs.

## Acceptance Criteria

- The endpoint returns a well-formed JSON payload even when no entries are configured.
- Misconfigured or missing units degrade to `status = down` without breaking the entire response.
- The implementation follows existing patterns used by `/api/vpn/status` and `/api/tunnels/status`.
