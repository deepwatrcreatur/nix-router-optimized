# Architectural Comparison: Linux/NixOS vs. FreeBSD/OPNsense for Edge Routers


> **Revised 2026-11-19 (revision 2).** Corrected after the panel review in
> [discussion 21](discussions/21-ecosystem-plan-review.md); corrections are
> marked *[rev 2]*. For the project's current state and priorities, see §0 of
> [`ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md`](ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md#0-revision-2-2026-11-19-project-state-and-review-findings).

**Status**: Architectural Evaluation & Platform Positioning  
**Target Repository**: `nix-router-optimized`  
**Date**: November 2026  

---

## 1. Introduction: The Two Edge Routing Paradigms

When designing a custom, high-performance edge router or homelab gateway, operators inevitably weigh two dominant open-source software philosophies:

1. **The FreeBSD Appliance Model (OPNsense / pfSense)**: A dedicated, turnkey operating system image built around FreeBSD's networking stack, the OpenBSD Packet Filter (`pf`), and an imperative web management interface backed by an XML configuration store.
2. **The Declarative Linux Model (`nix-router-optimized`)**: A typed, code-driven edge routing framework built on modern Linux networking primitives (Netfilter/nftables, FastTrack flowtables, eBPF/XDP, `systemd-networkd`, Keepalived) and orchestrated declaratively via **NixOS**, **Clan**, and **Den** aspects.

A common question arises: *Would anything be gained by migrating to a FreeBSD/OPNsense base, or does Linux lack the high-availability (CARP/pfsync) and firewall capabilities of BSD?*

This document provides a rigorous technical comparison between these two architectures, examining packet forwarding performance, high-availability state synchronization, driver offloads, and fleet lifecycle management.

---

## 2. Direct Technical Component Mapping

A widespread misconception is that FreeBSD technologies like CARP and pfsync have no direct equivalents in Linux. In reality, both operating systems implement RFC-standard and kernel-level protocols that map 1-to-1 in functionality:

| Capability / Concern | FreeBSD / OPNsense | Linux / `nix-router-optimized` | Architectural Comparison |
| :--- | :--- | :--- | :--- |
| **Virtual IP Redundancy** | **CARP** (Common Address Redundancy Protocol) | **Keepalived / VRRP** (RFC 5798; VRRPv3 is RFC 9568) | **Analogous roles, different protocols** *[rev 2: was "identical protocol logic"; CARP and VRRP share IP protocol 112 but differ in packet format and authentication]*: Both share floating VIPs via multicast/unicast heartbeats and elect master/backup nodes dynamically. VRRP is the vendor-neutral IETF standard used across enterprise networking (Cisco, Juniper, Arista). |
| **State Table Replication** | **pfsync** | **`conntrackd`** (FTFW Mode) | **Identical State Sharing**: `pfsync` multicasts pf state updates; `conntrackd` replicates Netfilter connection tracking events over an isolated management link. Both ensure established TCP/UDP flows survive failover without dropping sessions. |
| **Firewall Engine** | **pf** (Packet Filter) | **nftables** | **Linux Advantage**: `nftables` compiles into an in-kernel bytecode virtual machine with atomic rule replacement, native sets/maps, and higher lookup efficiency for large rule trees. |
| **Fast-Path Flow Offloading** | Hardware offload via FreeBSD drivers | **Netfilter Flowtables (FastTrack)** | **Linux Advantage**: Flowtables (`flow add @ft`) bypass the Netfilter evaluation pipeline for established connections, executing hardware/software fast-path forwarding at near line-rate. |
| **Kernel Bypass / Ring Filtering** | Netmap | **eBPF / XDP** (eXpress Data Path) | **Linux Advantage**: XDP executes programmable eBPF byte-code directly in the NIC driver ring buffer before the kernel allocates an `sk_buff`, enabling line-rate DDoS filtering and packet manipulation that FreeBSD cannot match. |
| **Multi-Queue Concurrency** | `net.isr` + RSS | **MSI-X IRQ Affinity + RPS/XPS** | **Parity**: Both can spread packet processing across CPU cores when configured properly; Linux offers fine-grained per-queue MSI-X core affinity and software steering masks. |
| **System Lifecycle & Config** | Imperative PHP / XML (`config.xml`) | **Nix Flakes + Clan + Den Aspects** | **NixOS Advantage**: reproducible builds, atomic generational upgrades, declarative configuration without runtime drift, and bootloader rollbacks *[rev 2: was "100% bit-identical" and "zero drift"; most, not all, store paths are bit-reproducible]*. |

---

## 3. Deep Dive: High Availability & State Synchronization

In FreeBSD appliances, high availability relies on the pair **CARP + pfsync**:
- **CARP** (layer 3) handles virtual IP election.
- **pfsync** (layer 4) broadcasts firewall state modifications across a dedicated sync interface.

In `nix-router-optimized`, the Linux equivalent is **Keepalived (VRRP) + `conntrackd`**:

```
                 CARP / pfsync (FreeBSD)               VRRP / conntrackd (Linux)
             ┌─────────────────────────────┐       ┌─────────────────────────────┐
Election:    │  CARP (Multicast Proto 112) │  ==   │  VRRP (Multicast Proto 112) │
             └──────────────┬──────────────┘       └──────────────┬──────────────┘
                            │                                     │
State Sync:  │  pfsync (Multicast/Unicast) │  ==   │   conntrackd (FTFW Mode)    │
             └─────────────────────────────┘       └─────────────────────────────┘
```

### Why `conntrackd` Matches `pfsync`
`conntrackd` running in **FTFW (Fault-Tolerant Firewall) mode**:
1. Hooks into Linux Netfilter connection tracking (`ctnetlink`).
2. Transmits state transitions (new connections, TCP handshakes, NAT translations) over an isolated out-of-band management subnet (e.g. `192.168.100.0/24`).
3. Maintains an external cache on the standby node.
4. Upon VRRP election victory, Keepalived triggers `conntrackd -c` *[rev 2: was `-C`]*, which injects the external cache into the standby node's kernel conntrack table.
5. In-flight TCP streams, VoIP/SIP calls, and established WireGuard tunnels continue flowing without connection resets (`RST`).

There is no technical feature in CARP/pfsync that Linux cannot deliver with VRRP/`conntrackd`.

---

## 4. Forwarding Performance: nftables + FastTrack vs. pf

### The FastTrack Advantage
Linux `nftables` supports **Flowtables** (inspired by MikroTik RouterOS FastPath/FastTrack):
- Traditional firewall: Every forwarded packet traverses the entire forward chain, evaluating interface rules, bogon filters, geo-IP sets, and NAT rules.
- FastTrack flowtable: Once a TCP/UDP connection is ESTABLISHED, the 5-tuple is entered into an in-kernel flowtable. Subsequent packets in that flow bypass the entire Netfilter rule tree and are forwarded directly to the egress interface driver.

This allows low-power x86 CPUs (like the Intel i7-3770 in `elitedesk` or Intel N100 mini-PCs) to route multi-gigabit traffic (2.5 Gbps / 10 Gbps) at **single-digit CPU utilization**.

### eBPF and XDP (eXpress Data Path)
Linux possesses an architectural advantage that FreeBSD fundamentally lacks: **XDP (eXpress Data Path)**.
- XDP programs run inside the network interface driver before the operating system even allocates an `sk_buff` packet structure.
- Malicious packets, DDoS floods, or bogons can be dropped (`XDP_DROP`) at tens of millions of packets per second without waking up the kernel network stack.
- FreeBSD's `netmap` provides raw packet access, but lacks the safe, in-kernel verifier, programmable bytecode, and native integration of Linux eBPF.

---

## 5. Lifecycle Management: The Declarative Fleet vs. The Imperative Appliance

The most decisive distinction between OPNsense and `nix-router-optimized` is not networking protocols, but **configuration management, testability, and operational safety**.

### The OPNsense Paradigm: The Single-Box Web Appliance
- **Configuration Storage**: A single monolithic XML file (`/conf/config.xml`).
- **Mutation Model**: Imperative changes made via a web UI or REST API modify `config.xml`, which triggers PHP backend scripts (`configd`) to regenerate daemon configurations on the fly.
- **Upgrades**: Upgrades are in-place binary replacements via FreeBSD `pkg`. If an upgrade fails or breaks driver compatibility, rollback is done by booting an older ZFS boot environment or restoring a configuration backup *[rev 2: OPNsense has supported boot environments and config backup/restore for years]*.
- **Fleet Integration**: Each OPNsense instance is an isolated island. Managing a pair of routers requires third-party tools, manual XML replication (HA sync), or custom API scripts.

### The `nix-router-optimized` Paradigm: Declarative Infrastructure as Code
- **Configuration Storage**: Typed, version-controlled Nix expressions structured in a Git repository.
- **Mutation Model**: Completely pure and deterministic. System configurations evaluate into deterministic Nix store derivations *[rev 2: evaluation is deterministic; build outputs are mostly, not always, bit-identical]*.
- **Upgrades & Atomic Rollback**: Every configuration change or package update produces a new NixOS **system generation**. If a change breaks connectivity, `deploy-rs` automatically rolls back within 30 seconds. In disaster scenarios, operators select an older generation from the GRUB bootloader menu to instantly restore a known-good state.
- **Fleet Synergy**: Routers are not isolated pets; they are first-class nodes in a multi-host homelab fleet (`nix-clan-homelab`). The exact same typed topology defines DNS records, firewall policies, DHCP pools, and monitoring targets across physical routers, hypervisors, and application hosts.
- **Compile-Time Verification**: `nix flake check` runs evaluation-time assertions, catching overlapping subnets, missing interface bindings, and configuration conflicts **before any byte is deployed to production hardware**.

---

## 6. Summary: When to Choose Which Platform

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Choose FreeBSD / OPNsense if:                                               │
│   • You want an immediate, turnkey, plug-and-play appliance out of the box. │
│   • You prefer a graphical web UI for day-to-day administration.            │
│   • Your infrastructure has no automated CI/CD, GitOps, or Nix tooling.    │
│   • You do not require multi-host declarative inventory synchronization.    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Choose NixOS / `nix-router-optimized` if:                                  │
│   • You want carrier-grade reproducibility, version control, and GitOps.   │
│   • You operate a multi-host fleet and want a single source of truth.       │
│   • You require atomic deployments with automated rollback on network loss. │
│   • You need Linux-exclusive performance primitives (FastTrack, XDP/eBPF).  │
│   • You value typed compile-time assertions over runtime configuration bugs.│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Conclusion

Migrating to a FreeBSD base would sacrifice the greatest architectural advantages of `nix-router-optimized`—declarative fleet integration, Nix flakes, atomic rollbacks, Clan/Den aspects, and FastTrack/XDP performance—without gaining any networking capability that Linux does not already provide through **VRRP + `conntrackd` + nftables**.
