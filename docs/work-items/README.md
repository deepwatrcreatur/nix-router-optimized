# Work Items

Start here if you are assigning another agent:

- [`START-HERE.md`](./START-HERE.md)

This folder is the working queue for router-flake follow-up that should be
tracked separately from the dashboard planning docs.

## How To Use

- Treat each file in this folder as one PR-sized work stream.
- Prefer one agent per file/branch.
- Mark the file as `in-progress` in its header once an agent starts it.
- When work is fully merged, either delete the file or keep it briefly as
  `done` if it records useful outcome notes for follow-up agents.
- `done` items must not remain in the active ranking.

## Current Ranked Queue

- [33-router-bgp-ha-boundaries-and-guardrails](./33-router-bgp-ha-boundaries-and-guardrails.md) — `in-progress`
- [34-router-bgp-auth-afi-and-policy](./34-router-bgp-auth-afi-and-policy.md) — `ready`

## Recently Completed

- [32-router-bgp-firewall-and-validation](./32-router-bgp-firewall-and-validation.md) — `done`
- [31-router-bgp-support-boundary-and-docs](./31-router-bgp-support-boundary-and-docs.md) — `done`
- [29-router-module-eval-and-smoke-skill](./29-router-module-eval-and-smoke-skill.md) — `done`
- [30-router-diag-and-boundary-skills](./30-router-diag-and-boundary-skills.md) — `done`
- [16-router-tunnels-module](./16-router-tunnels-module.md) — `done`
- [17-dashboard-tunnels-status-api](./17-dashboard-tunnels-status-api.md) — `done`
- [18-dashboard-tunnels-tab-widget](./18-dashboard-tunnels-tab-widget.md) — `done`
- [19-router-remote-admin-module](./19-router-remote-admin-module.md) — `done`
- [20-dashboard-remote-admin-status-api](./20-dashboard-remote-admin-status-api.md) — `done`
- [21-dashboard-remote-admin-tab-widget](./21-dashboard-remote-admin-tab-widget.md) — `done`
- [22-router-security-hardening-validation](./22-router-security-hardening-validation.md) — `done`
- [23-router-zones-policy-validation](./23-router-zones-policy-validation.md) — `done`
- [24-router-nptv6-module](./24-router-nptv6-module.md) — `done`
- [25-ipv6-vpn-policy-routing](./25-ipv6-vpn-policy-routing.md) — `done`
- [26-dynamic-prefix-watch-hook](./26-dynamic-prefix-watch-hook.md) — `done`
- [27-rfc8028-provisioning-domains](./27-rfc8028-provisioning-domains.md) — `done`
- [28-opencode-router-dashboard-restyle](./28-opencode-router-dashboard-restyle.md) — `done`

## Why This Structure

This repo already has a dashboard-heavy docs tree. A small separate queue makes
non-dashboard router features easier for agents to claim and implement.
