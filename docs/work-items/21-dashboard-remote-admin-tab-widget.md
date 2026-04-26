# Dashboard Remote Admin Tab & Widget

Status: done

Branch: `feat/dashboard-remote-admin-tab-widget`

## Goal

Add a dedicated Remote Admin tab to the router dashboard with a widget that displays remote administration entry status based on `/api/remote-admin/status`.

## Scope

- Add a "Remote Admin" tab and page container to the dashboard shell.
- Implement a `RemoteAdminWidget` that consumes `/api/remote-admin/status` and renders configured/active/warning/down counts.
- Show per-entry rows with type, name, systemd unit, URL, and description, plus empty-state guidance when no entries exist.

## Acceptance Criteria

- The Remote Admin tab appears in the sidebar and persists its layout like other pages.
- The widget handles missing or degraded data gracefully (clear error or empty states).
- Existing tabs continue to function unchanged.
