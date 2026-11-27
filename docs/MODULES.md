# NixOS Router Framework — Module Reference

This document provides a comprehensive reference for all modules available in `nix-router-optimized`.

---

## Core Networking & Routing

### `router-networking`
Reusable, router-oriented `systemd-networkd` configuration layer:
- **WAN Uplink**: DHCP, static IPv4/v6, router advertisements (`IPv6AcceptRA`), and DHCPv6 Prefix Delegation (`DHCPPrefixDelegationHint`).
- **Downstream Segments**: Routed LAN, management, and DMZ interfaces with declarative IP addresses.
- **VLAN Integration**: 802.1Q tagged sub-interfaces on WAN or LAN.
- **IPv6 Router Advertisements**: Per-interface `IPv6SendRA`, custom prefix delegation slices, RFC 8106 RDNSS DNS advertisement, and RFC 9686 IPv6-Only Preferred flag support.
- **Uplink Readiness**: `requiredForOnline` policies preventing boot hangs when WAN cables are disconnected.

### `router-dhcp`
Lightweight DHCP server layer powered directly by `systemd-networkd`:
- Automatically derives served subnets from `services.router-networking.routedInterfaces`.
- Per-segment IP pool sizing and static lease mapping.
- PXE/iPXE boot option advertisements (DHCP option 66/67) for netboot endpoints like iVentoy.

### `router-dhcp-relay`
DHCPv4 relay (RFC 1542) for routed segments via `systemd-networkd`'s relay mode:
- Forwards a segment's requests to a central DHCP server; no extra daemon.
- Option 82 Circuit ID (default: the device name) and Remote ID.
- Kea and `router-dhcp` skip relayed segments; firewall rules for clients and server replies.
- See [router-dhcp-relay.md](./router-dhcp-relay.md).

### `router-multicast`
IGMP proxy (igmpproxy) for IPTV-style multicast:
- Configurable upstream (often an ISP IPTV VLAN, not assumed to be the WAN) and listed downstreams.
- Firewall forwards `224.0.0.0/4` only to the listed downstreams; loose `rp_filter` on the upstream.
- quickleave, group allow/deny lists. See [router-multicast.md](./router-multicast.md).

### `router-ipsec`
Route-based site-to-site IPsec (strongSwan swanctl, IKEv2, PSK) with XFRM interfaces:
- One XFRM interface per tunnel; routing (static or BGP via `router-bgp`) decides what is encrypted.
- PSK read from a runtime file; IKE/ESP admitted only on the WAN from the peer; optional `router-zones` zone.
- See [router-ipsec.md](./router-ipsec.md).

### `router-kea`
ISC Kea DHCPv4 (and DHCPv6) server for advanced environments:
- Declarative pool ranges, subnet definitions, and static reservations.
- Optional RFC 2136/TSIG DDNS integration with local DNS servers (Technitium or BIND). TSIG secrets are loaded at runtime without leaking into the Nix store.
- DHCP option 42 integration with `router-ntp`.
- High Availability hooks and lease synchronization support.

### `router-pppoe`
Composable PPPoE uplink wrapper:
- Uses `services.pppd` as the PPPoE client daemon.
- References runtime secret files for ISP credentials (`/run/secrets/pppoe-peer.conf`), keeping credentials out of `/nix/store`.
- Seamlessly integrates with `router-networking` downstream segments.

### `router-mwan`
Prioritized multi-WAN uplink failover:
- Monitors gateway health via tracking IPs (`1.1.1.1`, `8.8.8.8`) with automated metric switching.
- Prioritized failover between primary ISP and backup connections (e.g. 5G/LTE cellular backup).
- Note: Intended for prioritized failover, not dynamic packet-level ECMP load balancing.

---

## Firewall, Security & Zones

### `router-firewall`
Role-aware nftables firewall policy derived from router interface topology:
- Derives interface roles (WAN, LAN, management) automatically from `router-optimizations.interfaces`.
- FastTrack / Netfilter flowtable acceleration with SIP/VoIP exclusion options (`flowtable.sipFriendly.enable`).
- TCP MSS clamping for PPPoE and reduced-MTU links.
- Hairpin NAT for LAN clients accessing internal services via external domains.
- Egress bogon filtering and Geo-IP country blocking sets.

### `router-zones`
Declarative zone-based security abstractions:
- Group physical interfaces and VLANs into logical security zones (`wan`, `lan`, `iot`, `guest`, `dmz`).
- Declarative cross-zone forwarding matrix (e.g. `lan -> wan: accept`, `iot -> lan: drop`, `guest -> wan: accept`).
- Automatic generation of dedicated nftables chains per zone.

### `router-security-hardened`
Kernel-level security tuning and edge defenses:
- OpenBSD-tier kernel hardening: restricted `dmesg`, ASLR enforcement, TCP SYN cookie protection, reverse-path filtering (`rp_filter`, strict by default, `loose` for VRRP and multi-WAN), disabled ICMP redirects, and unused protocol modules refused even on explicit load.
- Inbound Geo-IP filtering via nftables sets.
- MAC address whitelisting per interface.

### `router-network-security`
Passive and inline network security sensors:
- Native wrapper for **Suricata** IDS/IPS with AF_PACKET packet capture and EveBox web interface.
- Lightweight sensor wrappers for **Snort 3** and **Zeek**.

---

## High Availability & Failover

### `router-ha`
Dual-node high availability engine powered by Keepalived (VRRP v2/v3, RFC 5798):
- **Floating Gateway VIP**: Shared Virtual IP (e.g. `10.10.10.1/16`) on LAN.
- **Golden MAC Cloning**: Clones the ISP-expected MAC address onto the active master node, allowing seamless ISP modem failover over an unmanaged switch.
- **Preemption Delay**: `preemptDelay` allows a recovered master to wait as BACKUP before reclaiming the VIP, preventing flapping.
- **Single-Active Unit Control**: Automatically starts exclusive services (DHCP, DDNS, UPnP, IPv6 RA) on master promotion and stops them on demotion.

### `router-apply`
Commit-confirm style switching (`router-apply diff|switch|confirm|revert|status`):
activates a new system for a trial, reverts after a timeout unless confirmed,
and previews the rendered config change. See
[`router-apply-safety.md`](./router-apply-safety.md#automatic-revert-router-apply).

---

## DNS & Ingress

### `router-dns-service`
Provider-aware local resolver abstraction:
- Selects between `technitium`, `unbound`, and `dnsmasq`.
- Configures static `/etc/resolv.conf` and disables systemd-resolved when appropriate.
- Forwarding and upstream DNS configuration.

### `router-technitium`
Comprehensive Technitium DNS server integration:
- Automated API token provisioning from the admin password secret.
- Secondary zone replication over TSIG-signed AXFR/IXFR from primary to standby router nodes.
- Declarative DHCP reservations and DNS record synchronization.
- Native DoH/DoT/DoQ configuration.

### `dns-blocklists`
Declarative Technitium DNS ad-blocking and threat intelligence:
- Curated presets: `stevenblack`, `oisd-big`, `hagezi-light`, `hagezi-normal`, `hagezi-pro`, `hagezi-ultimate`, `hagezi-nrd-14d`.
- Additive custom blocklist URLs and configurable update schedules.

### `router-ddns`
Thin Dynamic DNS updater using `inadyn`:
- Native Cloudflare API token support loaded from runtime files.
- Automatically updates apex (`@`) and subdomains (`homelab`, `vpn`, etc.) on WAN address changes.
- On a `router-ha` pair, `ha.singleActiveOwner` runs updates on the VRRP MASTER only.

### `caddy-reverse-proxy`
Declarative reverse proxy with automated Let's Encrypt / ACME TLS certificates:
- Internal split-DNS and external public routing rules.
- Per-service upstream reverse proxy configuration and root-domain redirects.

---

## IPv6 Transition Technologies

### `router-nat64` & `router-dns64`
Stateless NAT64 translation via Tayga and AAAA record synthesis via Unbound:
- Allows IPv6-only clients to reach legacy IPv4 internet hosts transparently.
- Default RFC 6052 Well-Known Prefix (`64:ff9b::/96`) or custom prefix mapping.

### `router-clat`
Experimental client-side translation (464XLAT CLAT) surface:
- Translates IPv4 traffic to IPv6 for uplinks that only route native IPv6.
- Contract-oriented validation and firewall rules.

### `router-nptv6`
IPv6-to-IPv6 Network Prefix Translation (RFC 6296):
- Stateless 1:1 translation between Unique Local Addresses (ULA) and Global Unicast Addresses (GUA).

### `router-ndp-proxy`
Neighbor Discovery Protocol proxy via `ndppd`:
- Proxies IPv6 neighbor solicitations for routed prefixes across multi-interface topologies.

---

## VPNs & Remote Access

### `router-tailscale`
Router-aware Tailscale integration:
- Configures subnet routing (advertising LAN and management subnets) and exit node roles.
- Automatic nftables firewall policy integration.

### `router-wireguard`
Declarative WireGuard site-to-site and roadwarrior server wrapper:
- WAN UDP port opening, peer key management, and LAN/WAN forwarding rules.

### `router-cloudflare-tunnel`
Cloudflare Tunnel (`cloudflared`) wrapper:
- Publishes selected internal services without opening inbound firewall ports.
- Auto-registers tunnel status in the router dashboard.

### `router-cloudflare-warp`
Outbound Cloudflare WARP client with selective LAN IP policy routing:
- Allows routing designated bulk downloaders or workstations through Cloudflare WARP while keeping ordinary traffic on the native ISP link.

### `router-openvpn`, `router-netbird`, `router-zerotier`, `router-headscale`, `router-pangolin`, `router-twingate`
Dedicated wrappers for overlay mesh networks, point-to-point tunnels, and remote access gateways.

---

## Observability & Performance

### `router-optimizations`
Kernel tuning, hardware offloading, and queue optimization:
- Python-based dynamic driver negotiation (TSO, GSO, GRO on; LRO suppressed for routers).
- Ethtool ring buffer pre-set tuning.
- Sysctl optimization for routing throughput and conntrack table sizing.

### `router-observability`
Netfilter flow logging:
- ulogd2 on an NFLOG group, text (`logemu`, `/var/log/ulogd/flow.log`) by default or JSON (`ulogdOutputPlugin = "json"`, `/var/log/ulogd/flow.json`; needs the flake overlay's ulogd).
- Vector parses the JSON log and forwards it to the journal and, with `exportLogs`, to an upstream Vector. It runs only with JSON output (`enableVector` defaults to that), so don't list `vector` in `router-dashboard.services` on a `logemu` router.

### `router-slices`
Systemd resource slice hierarchy:
- `router-core.slice`: Guarantees CPU and memory priority for packet forwarding and core networking.
- `router-observability.slice`: Constrains Netdata, Prometheus, and logging agents so telemetry spikes never starve routing.
- `router-applications.slice`: Isolates user applications and auxiliary services.

### `router-alerting`
Alert delivery for the router's Prometheus ([guide](router-alerting.md)):
- Alertmanager with ntfy, email, webhook and any native receiver (Telegram, Discord, Pushover, ...), secrets as `*File` options.
- Dead-man watchdog for healthchecks.io-style services, so "router down" is reported too.
- Optional notification when a new device gets its first DHCP lease (Kea `run_script` hook).

### `router-dashboard`
Lightweight web dashboard on port 8888:
- Real-time interface bandwidth (RX/TX speeds and totals).
- WAN IP, gateway health, active connections, and uptime. Gateway health pings the default gateway plus `gatewayHealth.targets` (default 1.1.1.1 and 8.8.8.8).
- Service status, VPN status, and declarative tunnel overview.

### `router-homelab`
Homelab service bundle:
- Pre-provisions Prometheus, Grafana, Netdata, and dashboard quick-links.
- Automatically formats dashboard links with proper bracketed IPv6 literals and routed LAN addresses.

### `router-ntopng`
Optional ntopng integration for Layer-7 application flow analysis and bandwidth profiling.

### `router-log-storage`
Partitioning strategy for persistent journal and service logs on dedicated secondary storage.
