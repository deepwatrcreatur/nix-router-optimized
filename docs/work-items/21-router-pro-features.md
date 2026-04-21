# Work Items: Pro-Router Features

This document tracks the implementation of advanced routing features for the `nix-router-optimized` flake, aimed at providing a "RouterOS-like" experience on NixOS.

## 1. Smart Queue Management (SQM) / Bufferbloat Control (CAKE)
- **Status**: ✅ Completed
- **Goal**: Eliminate lag during high link saturation by implementing the CAKE (Common Applications Kept Enhanced) queuing discipline.
- **Tasks**:
  - [x] Create `modules/router-sqm.nix`.
  - [x] Support per-interface bandwidth shaping (ingress/egress).
  - [x] Integrate with `router-networking`.
  - [x] Add dashboard status for SQM (via service monitoring).

## 2. mDNS Repeater / Avahi Reflector
- **Status**: ✅ Completed
- **Goal**: Enable service discovery (AirPlay, Chromecast) across isolated VLANs.
- **Tasks**:
  - [x] Create `modules/router-mdns.nix`.
  - [x] Configure Avahi in "reflector" mode.
  - [x] Add firewall rules to allow mDNS (UDP 5353) on participating interfaces.

## 3. UPnP/IGD (MiniUPnPd)
- **Status**: ✅ Completed
- **Goal**: Support dynamic port forwarding for gaming/P2P with strict security controls.
- **Tasks**:
  - [x] Create `modules/router-upnp.nix`.
  - [x] Support "secure mode" (clients only map ports to themselves).
  - [x] Integrate with `nftables`.

## 4. Wake-on-LAN (WoL) Relay/Proxy
- **Status**: ✅ Completed (Existing feature in Dashboard)
- **Goal**: Wake internal machines from VPN or Dashboard.
- **Tasks**:
  - [x] Verified existing implementation in `server.py`.

## 5. FRR (Free Range Routing) Integration
- **Status**: ✅ Completed
- **Goal**: Support BGP/OSPF for dynamic routing with Proxmox/K8s clusters.
- **Tasks**:
  - [x] Create `modules/router-bgp.nix`.
  - [x] Provide simplified BGP peering templates.

## 6. High Availability (HA) - VRRP (Keepalived)
- **Status**: ✅ Completed
- **Goal**: Share a Virtual IP (VIP) between two routers for seamless failover.
- **Tasks**:
  - [x] Create `modules/router-ha.nix`.
  - [x] Integrate with `keepalived`.
  - [x] Add VRRP firewall rules.
  - [x] Implement WAN tracking/failover with MAC cloning.

## 7. Kea DHCP High Availability
- **Status**: ✅ Completed
- **Goal**: Redundant DHCP services with lease synchronization.
- **Tasks**:
  - [x] Extend `modules/router-kea.nix` with HA hook configuration.
  - [x] Support load-balancing and failover modes.
  - [x] Open HA control ports in firewall.

## 8. WAN MAC Cloning
- **Status**: ✅ Completed
- **Goal**: Support ISP handover by cloning MAC addresses on WAN interfaces.
- **Tasks**:
  - [x] Update `modules/router-networking.nix` with `macAddress` support.

## 9. Multi-WAN Failover
- **Status**: ✅ Completed
- **Goal**: Support multiple ISPs with automatic health-checking and metric-based failover.
- **Tasks**:
  - [x] Refactor `router-networking.nix` to support multiple `wans`.
  - [x] Create `modules/router-mwan.nix` for health monitoring.
  - [x] Implement dynamic route metric switching.

## 10. Security & Hardening (The "OpenBSD" Tier)
- **Status**: 📅 Planned
- **Goal**: Bring NixOS as close to OpenBSD security standards as possible.
- **Tasks**:
  - [ ] Add `router-security-hardened.nix` module.
  - [ ] Implement declarative Geo-IP blocking (via nftables sets).
  - [ ] Strict Kernel parameter tuning (ASLR, module disabling, dmesg restriction).
  - [ ] MAC-address white-listing/alerting for trusted segments.
  - [ ] Update project README and documentation to discuss these new security features.
  - [ ] Tag a new release with detailed release notes covering all "Pro-Router" enhancements.

---

# Documentation: Advanced Features

## SQM (Cake)
SQM is the most effective way to combat **Bufferbloat**. It manages how packets are queued when an interface is saturated. 
- **CAKE** is the preferred qdisc as it handles NAT-awareness and fairness across hosts automatically.
- **Usage**: Set your `uploadSpeed` and `downloadSpeed` to ~95% of your actual line speed.

## mDNS Reflector
By default, mDNS only works on a single Layer 2 segment. If your Phone is on `LAN` and your TV is on `IOT`, they won't see each other. The reflector repeats these packets across subnets safely.

## NAT64/DNS64
Enables an IPv6-only transition strategy. 
- **NAT64**: Translates IPv6 packets to IPv4 using the Tayga daemon.
- **DNS64**: Synthesizes AAAA records for IPv4-only domains via Unbound.
- **Prefix**: Defaults to the well-known `64:ff9b::/96`.
