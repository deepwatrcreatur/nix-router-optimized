# Architectural Comparison & Parity Plan: Linux/NixOS vs. VyOS for Edge Routers

**Status**: Architectural Evaluation & Engineering Parity Roadmap  
**Target Repository**: `nix-router-optimized`  
**Date**: November 2026  
**Companion Documents**: 
- [`FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md) (Linux/NixOS vs FreeBSD/pfSense/OPNsense)
- [`ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md`](./ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md) (NixOS Router Ecosystem & HA State)
- [`MODULES.md`](./MODULES.md) (Catalog of existing 38+ modules)

---

## 1. Executive Summary: The Two Declarative Paradigms

When network engineers seek an open-source, production-grade routing platform that rejects the rigid web GUIs of consumer appliances (OPNsense/pfSense) in favor of declarative, auditable configuration, two primary systems stand out:

1. **VyOS**: An enterprise network operating system (forked from Vyatta) based on Debian Linux, featuring a unified, hierarchical CLI syntax inspired by Juniper Junos / EdgeOS. VyOS provides a declarative configuration tree (`set ...`, `commit`, `save`) and comprehensive routing protocol support (FRRouting).
2. **`nix-router-optimized`**: A typed, declarative edge router framework built on native Linux networking primitives (`nftables`, FastTrack flowtables, `systemd-networkd`, Keepalived, Kea DHCP, Technitium DNS) and evaluated through **NixOS flakes, modules, and type assertions**.

Both projects target technically demanding users who value reproducibility, automation, and operational rigor. However, they approach declarativity from fundamentally different architectural foundations:

* **VyOS uses an Imperative-under-the-Hood Commit Engine**: The user writes declarative CLI commands, but VyOS translates them via procedural Python migration and validation scripts into running state. Upgrades between major versions (e.g., 1.3 to 1.4) can break due to migration script failures, and configuration state is mutable at runtime.
* **`nix-router-optimized` uses Pure Functional Compilation**: The entire operating system, network topology, firewall rulesets, and daemon configurations compile into an immutable, bit-reproducible Nix derivation. System upgrades produce atomic generations that can be rolled back instantaneously at the bootloader level.

### High-Level Verdict

`nix-router-optimized` is **not** behind VyOS in core performance or home/campus network architecture. In fact, `nix-router-optimized` already surpasses VyOS in:
* **Wire-speed FastPath Acceleration** (Netfilter FastTrack flowtables vs. standard conntrack).
* **Authoritative DNS Clustering** (Clustered Technitium with TSIG AXFR/IXFR vs. basic PowerDNS/dnsmasq forwarders).
* **Bufferbloat Mitigation** (Out-of-the-box CAKE SQM with diffserv vs. complex manual HTB/HFSC queuing).
* **Modern Zero-Trust Mesh Overlays** (Native Headscale, Tailscale, Netbird, Twingate, and Cloudflare Tunnels).

However, VyOS has spent over a decade polishing **enterprise cloud interconnects**, **interior gateway routing**, **routed multicast**, and **operational live inspection**. This document specifies how `nix-router-optimized` can systematically close those gaps.

---

## 2. Technical Component Mapping

| Functional Area | VyOS (1.4 / 1.5 Rolling) | `nix-router-optimized` (NixOS) | Evaluation & Parity Status |
| :--- | :--- | :--- | :--- |
| **Configuration Model** | Hierarchical CLI tree (`set`, `commit`, `save`) | Pure Nix modules, submodules, and eval assertions | **NixOS Superior**: Pure functional evaluation, compile-time type validation, zero runtime drift. |
| **System Lifecycle** | Mutable Debian base with overlayfs image snapshots | Immutable Nix store paths with generational bootloader rollbacks | **NixOS Superior**: Atomic upgrades with sub-second bootloader rollback to any past generation. |
| **Fast-Path Forwarding** | Standard Linux kernel conntrack (experimental XDP/flowtable) | **Netfilter Flowtables (FastTrack)** (`nftables-fasttrack.nix`) | **NixOS Advantage**: Established connections bypass conntrack/firewall inspection at wire speed (10G+). |
| **High Availability (HA)** | VRRPv2/v3 (Keepalived) + `conntrackd` sync | **Keepalived (VRRP) + `conntrackd` + Golden MAC cloning** (`router-ha.nix`) | **Parity+**: Both support stateful failover; `nix-router-optimized` handles ISP MAC lockouts and dynamic Kea/DNS ownership. |
| **BGP Routing** | FRRouting BGP (`protocols bgp`) | FRRouting BGP (`router-bgp.nix`) | **Parity**: Both drive FRR `bgpd` with prefix-lists and route-maps. |
| **OSPF / IS-IS Routing** | FRRouting OSPFv2/v3 (`protocols ospf`) | *Not implemented* | **VyOS Advantage**: Missing in `nix-router-optimized`. Needed for L3 core switch integration. |
| **Failure Detection** | BFD (`protocols bfd`) integrated with BGP/OSPF/VRRP | *Not implemented* (relies on standard keepalived / BGP timers) | **VyOS Advantage**: Missing in `nix-router-optimized`. Needed for sub-second (<300ms) link failover. |
| **Cloud / Site-to-Site VPN** | **Route-Based IPsec (VTI / IKEv2)**, DMVPN, WireGuard | WireGuard, OpenVPN, Tailscale, Headscale, Netbird | **VyOS Advantage**: Missing IPsec/VTI. Required for AWS, Azure, GCP, and corporate firewalls. |
| **Multicast Routing** | IGMP Proxy (`protocols igmp-proxy`) & PIM-SM | mDNS repeater only (`router-mdns.nix`) | **VyOS Advantage**: Missing in `nix-router-optimized`. Needed for ISP IPTV and cross-VLAN multicast. |
| **Traffic Shaping (QoS)** | HTB, HFSC, FQ-CoDel, CAKE | **CAKE SQM with diffserv** (`router-sqm.nix`) | **NixOS Advantage**: CAKE provides superior latency control without complex manual bandwidth bucket math. |
| **DNS Architecture** | PowerDNS Recursor / dnsmasq forwarder | **Clustered Technitium (Primary/Secondary AXFR/IXFR, DoH/DoT, DNSSEC)** | **NixOS Advantage**: Full authoritative split-horizon DNS server with dynamic Kea DDNS registration. |
| **Operational Inspection** | Unified `show ...` / `monitor ...` CLI hierarchy | Fragmented across `systemctl`, `networkctl`, `nft`, `conntrack`, `curl` | **VyOS Advantage**: VyOS operational ergonomics are significantly cleaner than raw Linux commands. |

---

## 3. The 4 High-Value Gaps: Technical Specifications

```
                     PHASED PARITY & ENHANCEMENT ROADMAP
   ┌────────────────────────────────────────────────────────────────────────┐
   │ Phase 1: Operational Inspection CLI (`router-cli`)                     │
   │          Unified runtime visibility (replaces 8 ad-hoc commands)       │
   ├────────────────────────────────────────────────────────────────────────┤
   │ Phase 2: Route-Based IPsec & Cloud Interconnects (`router-ipsec.nix`) │
   │          IKEv2 + strongSwan swanctl + VTI/XFRM + BGP over IPsec        │
   ├────────────────────────────────────────────────────────────────────────┤
   │ Phase 3: Interior Dynamic Routing & BFD (`router-ospf.nix`, `router-bfd`)
   │          FRRouting OSPFv2/OSPFv3 + sub-second link failure detection    │
   ├────────────────────────────────────────────────────────────────────────┤
   │ Phase 4: Routed Multicast & IPTV Proxy (`router-multicast.nix`)        │
   │          igmpproxy / smcroute for ISP ONT IPTV & smart media VLANs     │
   └────────────────────────────────────────────────────────────────────────┘
```

---

### Work Item 1: Unified Operational Inspection CLI (`router-cli`)

#### Motivation & Current Friction
In VyOS, an operator can inspect the entire system state with intuitive, hierarchical commands:
```bash
show interfaces
show ip route
show dhcp server leases
show vrrp
show conntrack table
```
In `nix-router-optimized`, inspecting live state requires remembering disparate utility commands, API tokens, and socket paths:
* DHCP leases: Querying Kea via REST API or inspecting `/var/lib/kea/`.
* DNS zones: `resolvectl` or Technitium API curls using an authentication token.
* HA state: `systemctl status keepalived` or inspecting `/run/keepalived/`.
* Flowtable offload: `nft list flowtable ip filter f`.
* Conntrack flows: `conntrack -L`.

#### Technical Design
Package a fast, zero-dependency Python or Bash CLI utility named `router` (or `router-cli`) in the flake:

```bash
router status          # High-level overview: node role (MASTER/BACKUP), WAN IP, throughput, flow count
router ha              # VRRP state, priority, heartbeat metrics, virtual IP status
router leases          # Pretty-printed active Kea DHCPv4 and DHCPv6 leases with hostnames
router dns [domain]    # Technitium query tool, zone health, and replication status
router routes          # Unified view of kernel FIB + FRR RIB (BGP/OSPF/static)
router flows           # Conntrack summary + active Netfilter FastTrack flowtable entries
router top             # Live interface bandwidth and PPS monitor
```

#### Implementation Path
1. Write a standalone Python script reading from:
   * `/run/keepalived/` or Keepalived JSON status FIFO.
   * Kea control socket (`/run/kea/kea4-ctrl-socket`).
   * Technitium local HTTP API (`http://127.0.0.1:5380/api/...` using the local admin token).
   * Linux `/proc/net/dev`, `ip -j route`, and `conntrack -S`.
2. Package the script as `pkgs.router-cli` and add it to `environment.systemPackages` when `services.router-networking.enable = true`.

---

### Work Item 2: Route-Based IPsec & Cloud Interconnects (`router-ipsec.nix`)

#### Motivation & Use Cases
While `nix-router-optimized` supports modern overlay VPNs (WireGuard, Tailscale, Headscale, Netbird), **IPsec remains the non-negotiable enterprise standard** for connecting edge routers to:
* **AWS Virtual Private Gateway & Transit Gateway**.
* **Azure VPN Gateway**.
* **Google Cloud VPN**.
* **Corporate Edge Firewalls** (Cisco ASA/FTD, Palo Alto Networks, Fortinet FortiGate, pfSense/OPNsense).

Public cloud VPNs mandate Route-Based IPsec (IKEv2) running BGP over Virtual Tunnel Interfaces (VTI) or XFRM interfaces.

#### Technical Design
Create `modules/router-ipsec.nix` backed by **strongSwan** using the modern `swanctl` backend (avoiding legacy `ipsec.conf`):

```nix
services.router-ipsec = {
  enable = true;
  
  connections."aws-transit-gateway" = {
    remoteAddress = "52.14.x.x";
    localAddress = "wan"; # Resolved from services.router-networking.wan.interface
    ikeVersion = 2;
    preSharedKeyFile = "/run/credentials/aws-vpn-psk";
    
    # Virtual Tunnel Interface
    vti = {
      interfaceName = "vti-aws";
      localTunnelAddress = "169.254.100.2/30";
      remoteTunnelAddress = "169.254.100.1/30";
      mtu = 1436;
    };
    
    proposals = {
      ike = [ "aes256gcm16-sha384-modp2048" ];
      esp = [ "aes256gcm16-modp2048" ];
    };
  };
};
```

#### Integration Points
1. **Network Layer**: Generates `systemd.network.netdevs."10-vti-aws".netdevConfig = { Name = "vti-aws"; Kind = "vti"; }` (or `xfrm`).
2. **Routing Layer**: Enables BGP peering over `vti-aws` via [`router-bgp.nix`](./router-bgp.md).
3. **Firewall Layer**: Automatically opens UDP ports 500/4500 and IP protocol 50 (ESP) on the WAN interface, and places `vti-+` interfaces into the appropriate firewall zone.

---

### Work Item 3: Interior Dynamic Routing — OSPFv2/OSPFv3 & BFD

#### Motivation & Use Cases
1. **L3 Core Switches in Homelabs/Campuses**: In networks with managed switches (e.g., Brocade ICX, Cisco, Aruba, MikroTik CRS), static routes become unmaintainable as subnets grow. OSPF dynamically redistributes local subnets and handles redundant internal links.
2. **Sub-second Failure Detection (BFD)**: Standard routing protocol dead timers are slow (3–30 seconds). Bidirectional Forwarding Detection (BFD, RFC 5880) sends microsecond heartbeats to detect physical or intermediate link breaks in <300ms, immediately triggering BGP/OSPF reconvergence or VRRP failover.

#### Technical Design
1. **`router-ospf.nix`**:
   * Extends the FRRouting daemon configuration established in [`router-bgp.nix`](./router-bgp.md).
   * Spawns `ospfd` (IPv4) and `ospf6d` (IPv6).
   * Declarative options:
     ```nix
     services.router-ospf = {
       enable = true;
       routerId = "10.10.10.1";
       areas."0.0.0.0" = {
         networks = [ "10.10.10.0/24" "10.10.20.0/24" ];
         interfaces = [ "enp6s16" "vlan20" ];
         passiveInterfaces = [ "vlan20" ]; # Announce subnet without sending hello packets
       };
       redistribute = [ "connected" "bgp" ];
     };
     ```
2. **`router-bfd.nix`**:
   * Configures FRR `bfdd`.
   * Defines peers with sub-second transmission/receive intervals:
     ```nix
     services.router-bfd = {
       enable = true;
       peers = {
         "10.10.10.2" = {
           detectMultiplier = 3;
           minRxInterval = 300; # ms
           minTxInterval = 300; # ms
         };
       };
     };
     ```
   * Ties into BGP and Keepalived track scripts.

---

### Work Item 4: Routed Multicast & IPTV Proxy (`router-multicast.nix`)

#### Motivation & Use Cases
* **ISP Linear IPTV (Set-top Boxes)**: Many FTTH/FTTC providers (e.g., Deutsche Telekom Magenta, Orange, KPN, Bell Fibe) deliver live television over IGMPv3 multicast streams. Replacing an ISP gateway with a custom router causes IPTV streams to freeze after 5–10 seconds because the router does not forward IGMP membership reports to the upstream ONT.
* **Smart Home Media Across Subnets**: While mDNS repeats zero-configuration discovery ([`router-mdns.nix`](./router-mdns.md)), certain streaming devices (e.g., Sonos, multi-room audio, proprietary security cameras) require true IP multicast forwarding across isolated VLANs.

#### Technical Design
Create `modules/router-multicast.nix` integrating `igmpproxy` or `smcroute`:

```nix
services.router-multicast = {
  enable = true;
  backend = "igmpproxy"; # or "smcroute"
  
  upstream = {
    interface = "enp6s17"; # WAN interface
    altnets = [ "10.0.0.0/8" "217.0.119.0/24" ]; # ISP multicast streaming sources
  };
  
  downstream = {
    interfaces = [ "vlan30-media" ];
  };
  
  quickleave = true;
};
```

#### Firewall Automation
The module automatically inserts `nftables` rules allowing:
* IGMP protocol (IP protocol 2) on the WAN interface.
* UDP destination range `224.0.0.0/4` forwarded from WAN to the designated downstream media VLANs.

---

## 4. Secondary Enterprise Features (Long-Term Horizon)

The following capabilities are present in VyOS but represent specialized enterprise use cases with lower ROI for typical edge/homelab deployments. They can be pursued as community interest warrants:

1. **BGP EVPN with VXLAN Overlays**:
   * *VyOS*: `interfaces vxlan` + `protocols bgp l2vpn evpn`.
   * *NixOS Reality*: `systemd-networkd` already natively supports `[VxLAN]` netdevs. Pairing this with FRR EVPN would enable data-center style Layer 2 fabric extensions across Layer 3 boundaries.
2. **DHCP Relay & Option 82**:
   * *VyOS*: `service dhcp-relay`.
   * *NixOS Reality*: In campus environments with centralized enterprise DHCP (Active Directory, Infoblox), the edge router acts merely as an RFC 3046 relay agent injecting circuit IDs.
3. **NetFlow / IPFIX Flow Collector Export**:
   * *VyOS*: Built-in `system flow-accounting` using `uacctd` / `pmacct`.
   * *NixOS Reality*: `nix-router-optimized` already has [`router-observability.nix`](./router-observability.md) (Vector + ulogd NFLOG + Prometheus metrics) and [`router-ntopng.nix`](./router-ntopng.md), which offer modern web-native observability.

---

## 5. Phased Implementation Roadmap & Effort Estimates

| Phase | Milestone / Component | Effort | Primary Dependencies | Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **Operational Inspection CLI (`router-cli`)** | Low (2–3 days) | Python/Bash, local APIs (`keactl`, Technitium, Keepalived) | **Immediate UX Leap**: Gives operators VyOS/Junos-style operational visibility without sacrificing declarative Nix. |
| **Phase 2** | **Route-Based IPsec (`router-ipsec.nix`)** | Medium (3–5 days) | `strongswan` (swanctl), `systemd-networkd` VTI/XFRM | **Enterprise & Cloud Gate**: Unlocks AWS Transit Gateway, Azure, GCP, and corporate firewalls. |
| **Phase 3** | **OSPFv2/v3 & BFD (`router-ospf.nix`, `router-bfd.nix`)** | Medium (3–4 days) | `frr` daemon infrastructure from `router-bgp.nix` | **Campus & Core Scale**: Integrates with L3 switches; provides sub-second link fault convergence. |
| **Phase 4** | **Routed Multicast (`router-multicast.nix`)** | Low-Medium (2 days) | `igmpproxy` / `smcroute`, `nftables` | **Consumer FTTH Support**: Fixes ISP IPTV and isolated AV VLAN streaming. |

---

## 6. Summary: The Value Proposition

`nix-router-optimized` does not need to duplicate every legacy protocol in VyOS (such as RIP, IS-IS, or PPPoE access concentrators) to be the superior platform. 

By closing the **four strategic gaps** outlined above:
1. Operators gain the operational elegance and cloud compatibility of VyOS.
2. Operators retain the unparalleled power of **pure functional NixOS evaluation, FastTrack flowtable line-rate forwarding, and atomic bootloader rollbacks**.
