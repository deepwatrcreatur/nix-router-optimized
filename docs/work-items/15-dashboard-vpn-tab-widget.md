# Dashboard VPN Tab Widget

Status: ready

Branch: `feat/dashboard-vpn-tab-widget`

## Goal

Add a VPN tab view that shows router VPN status clearly, including the
WireGuard-style peer rows the operator wants visible from the dashboard.

## Scope

- Add a VPN status widget backed by `/api/vpn/status`.
- Place the widget on the VPN tab created by the tab shell work.
- Show each VPN family and instance with status, interface, service unit, and
  peer/session details when available.
- Include empty-state guidance for routers with no configured VPN metadata.

## Acceptance Criteria

- VPN status is visible from a dedicated VPN tab.
- Healthy, warning, and down states are visually distinct.
- WireGuard peers can display latest handshake information when available.
- The widget handles mixed VPN deployments without assuming only one provider.
