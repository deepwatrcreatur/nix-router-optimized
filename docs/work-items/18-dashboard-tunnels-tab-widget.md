# Dashboard Tunnels Tab & Widget

Status: done

Branch: `feat/dashboard-tunnels-tab-widget`

## Goal

Add a dedicated Tunnels tab to the router dashboard with a widget that displays
application tunnel status based on `/api/tunnels/status`.

## Scope

- Add a "Tunnels" tab and page container to the dashboard shell.
- Implement a `TunnelsWidget` that consumes `/api/tunnels/status` and renders
  configured/active/warning/down counts.
- Show per-tunnel rows with provider, name, systemd unit, and public URL, with
  empty-state guidance when no tunnels exist.

## Acceptance Criteria

- The Tunnels tab appears in the sidebar and persists its layout like other
  pages.
- The widget handles missing or degraded tunnel data gracefully (clear error or
  empty states).
- No changes are required to existing tabs to keep them functioning.
