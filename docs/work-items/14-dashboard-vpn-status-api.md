# Dashboard VPN Status API

Status: done

Branch: `feat/dashboard-vpn-status-api`

## Goal

Expose a dashboard API endpoint that summarizes VPN service and interface
status for the router's declarative VPN modules.

## Scope

- Add a `/api/vpn/status` endpoint.
- Report configured VPN units/interfaces from Nix-provided dashboard metadata.
- Cover WireGuard, OpenVPN, Tailscale, Headscale, NetBird, and ZeroTier where
  the module is present/configured.
- Include unit active state, interface state, peer/session counts where safely
  available, and a concise health status.
- Avoid requiring dashboard write access or privileged secret reads.

## Acceptance Criteria

- The endpoint returns useful data even if some VPN tools are missing.
- It degrades to unknown/unavailable states rather than failing the whole
  response.
- Router dashboard module options generate the metadata needed by the API.
- Evaluation tests cover at least one enabled VPN module feeding dashboard
  metadata.
