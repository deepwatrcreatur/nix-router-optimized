# Dashboard Tunnels Status API

Status: done

Branch: `feat/dashboard-tunnels-status-api`

## Goal

Expose a `/api/tunnels/status` endpoint in the router dashboard API that
summarizes configured application tunnels (zrok, ngrok, other) using declarative
metadata from the router-tunnels module.

## Scope

- Accept tunnel metadata from the dashboard service environment (JSON), similar
  to `DASHBOARD_VPNS`.
- Implement `/api/tunnels/status` returning configured/active/warning/down
  counts and a list of tunnels with provider, name, unit, public URL, and
  status.
- Derive runtime health from systemd unit state and presence of a public URL,
  without calling provider APIs.

## Acceptance Criteria

- The endpoint returns a well-formed JSON payload even when no tunnels are
  configured.
- Misconfigured or missing units degrade to `status = down` without breaking the
  entire response.
- The implementation follows existing patterns used by `/api/vpn/status`.
