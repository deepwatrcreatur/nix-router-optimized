# Changelog

Notable changes to `nix-router-optimized`. Each release has full notes under
[`docs/releases/`](docs/releases/) and a matching
[GitHub release](https://github.com/deepwatrcreatur/nix-router-optimized/releases).
Versions are `0.x`: a minor release may change options, with each change listed
here (see [`docs/STABILITY.md`](docs/STABILITY.md)).

## Unreleased

Everything merged to `main` since v0.10.0 (2026-04-24).

### Breaking

- `services.router-ha.vrrpPassword` no longer defaults to `"nix-router-ha"`, which ended up in
  the world-readable Nix store. Set `vrrpPasswordFile` (preferred) or `vrrpPassword`; exactly
  one is required. Use the same value on both nodes, or the pair elects two masters. (#153)
- `services.router-ha.keaSync` is retired and only warns. It opened TCP 8000 on every
  interface and configured nothing. Kea HA is configured under `services.router-kea.dhcp4.ha`,
  and its port is now open to the peer only. (#156)
- Routed interfaces default `IPv6AcceptRA` to false.

### Added

- **HA:**
  - WAN health-check handover (`wan.healthCheck`);
  - shared DUID so the delegated prefix survives failover;
  - typed single-active ownership for RAs, DDNS, UPnP and Kea D2;
  - ordered transitions through `notify_fifo`;
  - `peerWaitSec`;
  - IPv6 RAs from a virtual link-local;
  - VRRP unicast peers for LANs that drop VRRP multicast;
  - Kea `dhcp4.ha.mode = "hot-standby"`;
  - Technitium zone replication that follows VRRP.
- **New modules:**
  - `router-dhcp-relay` (option 82);
  - `router-multicast` (IGMP proxy for IPTV);
  - `router-ipsec` (route-based, XFRM interfaces);
  - `router-alerting` (ntfy, email, webhooks);
  - `router-pangolin`, `router-twingate` and `router-cloudflare-warp`;
  - `router-clat` with a Tayga backend.
- **Operations:**
  - `router-apply`, a commit-confirm style switch with auto-revert;
  - `routerctl` subcommands for HA, leases, DNS and routes;
  - a Router Hardware Grafana dashboard with NIC and SFP sensors;
  - `*File` secret options so modules work without agenix.
- **Dashboard:**
  - authenticated service control;
  - inventory and reservation views;
  - light theme;
  - configurable gateway-health targets (`gatewayHealth.targets`).
- **Tests:** a multi-node QEMU harness and 14 VM tests, including HA pair failover, Kea HA,
  DHCP relay, IPsec, multicast and IPv6 downstream.

### Fixed

- HA WAN DHCP clients never send RELEASE on demotion. (#189)
- `tailscaled-autoconnect` retries after a start timeout. (#192)
- Pangolin's gerbil is pinned to 1.5.2 or later, so stopping it no longer panics. (#198)
- `dns-zone` no longer touches Secondary zones or zones owned by VRRP. (#188)

[`docs/releases/v0.7.0.md`](docs/releases/v0.7.0.md) was written on 2026-04-26 for a
v0.7.0 that was never tagged. It describes features that are part of this section.

## Releases

| Version | Date | Notes |
| :--- | :--- | :--- |
| v0.10.0 | 2026-04-24 | [Kea HA local address, lease commands, `outboundInterface`](docs/releases/v0.10.0.md) |
| v0.6.0 | 2026-03-14 | [Declarative Technitium blocklists](docs/releases/v0.6.0.md) |
| v0.5.0 | 2026-03-14 | [Dashboard phase 5, threaded backend, monitoring fixes](docs/releases/v0.5.0.md) |
| v0.9.0 | 2026-03-12 | External DNS zone configuration (`dns-zone` module) |
| v0.8 | 2026-03-12 | Arbitrary interface configuration and interface roles (WAN, LAN, OPT, MGMT) |

The early tags are out of order: v0.8 and v0.9.0 were tagged on 2026-03-12 at commits that
come before v0.5.0. Versions from v0.10.0 onwards increase with history.
