# Repository Documentation

This directory contains operator guides, support-boundary notes, implementation
status docs, archived discussions, and agent-facing work items for
`nix-router-optimized`.

Start with the smallest document that matches your question instead of guessing
from module names alone.

## Start Here By Topic

### IPv6 and translation

- [`router-ipv6-approach-guide.md`](./router-ipv6-approach-guide.md) — first stop
  for choosing among native IPv6, multi-prefix/PvD, NPTv6, NAT64/DNS64, CLAT,
  and NDP proxy approaches
- [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md) — decision ladder for
  IPv6 multi-uplink design
- [`IPV6-PVD.md`](./IPV6-PVD.md) — Provisioning Domains / native multi-prefix
  signaling
- [`router-nat64-dns64.md`](./router-nat64-dns64.md) — current NAT64 + DNS64
  usage and caveats
- [`DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md) — current experimental CLAT
  boundary
- [`router-ndp-proxy.md`](./router-ndp-proxy.md) — NDP proxy support boundary,
  module usage, static-path guidance, and verification steps
- [`router-translation-backends.md`](./router-translation-backends.md) —
  backend-boundary note for Tayga now and possible future Jool work

### HA and ownership boundaries

- [`router-ha-ownership.md`](./router-ha-ownership.md) — active-owner and shared
  capability boundary
- [`router-dhcp-single-active.md`](./router-dhcp-single-active.md) — why the
  current reference DHCP posture is single-active with manual promotion
- [`router-kea-ha-reentry-gate.md`](./router-kea-ha-reentry-gate.md) — evidence
  gate for any future Kea HA re-entry

### Service/module selection

- [`DHCP_SELECTION.md`](./DHCP_SELECTION.md) — DHCP backend choice guide
- [`router-mwan.md`](./router-mwan.md) — multi-WAN failover boundary
- [`router-bgp.md`](./router-bgp.md) — current BGP support boundary
- [`router-zones.md`](./router-zones.md) — zone/isolation model
- [`router-security-hardened.md`](./router-security-hardened.md) — hardening
  surface, including Geo-IP, WAN egress bogon blocking, and MAC controls
- [`router-runtime-credential-discipline.md`](./router-runtime-credential-discipline.md) —
  credential-passing audit and runtime-file boundary
- [`router-security-validation.md`](./router-security-validation.md) —
  post-change router-local, LAN-side, and WAN-side security validation runbook
- [`router-apply-safety.md`](./router-apply-safety.md) — manual pre-change,
  post-change, and rollback procedure for risky router updates

### Contributor and maintainer docs

- [`module-authoring.md`](./module-authoring.md) — how to add new modules to the
  flake
- [`router-ci-check-surface-audit.md`](./router-ci-check-surface-audit.md) —
  check-surface / CI boundary
- [`router-nix-ci-baseline.md`](./router-nix-ci-baseline.md) — Nix CI baseline
  notes
- [`troubleshooting.md`](./troubleshooting.md) — operator troubleshooting notes

### Dashboard docs

- [`IMPLEMENTATION-STATUS.md`](./IMPLEMENTATION-STATUS.md) — dashboard/status
  implementation snapshot
- [`DASHBOARD-ENHANCEMENT-PLAN.md`](./DASHBOARD-ENHANCEMENT-PLAN.md) — dashboard
  plan
- [`DASHBOARD-ARCHITECTURE.md`](./DASHBOARD-ARCHITECTURE.md) — dashboard
  architecture details
- [`DASHBOARD_SERVICE_CONTROL.md`](./DASHBOARD_SERVICE_CONTROL.md) — dashboard
  mutation boundary
- [`CURRENT-STATE.md`](./CURRENT-STATE.md) — older dashboard-state analysis
- [`OPNSENSE-RESEARCH.md`](./OPNSENSE-RESEARCH.md) — dashboard/product research

### History and execution

- [`discussions/`](./discussions/) — archived design/support-boundary
  discussions
- [`work-items/`](./work-items/) — active and recent execution queue
- [`releases/`](./releases/) — release notes
- [`incidents/`](./incidents/) — incident records

## Organization Notes

- Repo-local support-boundary docs are preferred over chat history.
- The root [`README.md`](../README.md) gives a feature overview; this directory
  is where the more honest usage and boundary docs live.
- If a topic has both a feature doc and a discussion round, treat the feature doc
  as the current operator guide and the discussion as design history.
