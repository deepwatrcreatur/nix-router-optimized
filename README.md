# NixOS Router Framework (`nix-router-optimized`)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white)](https://nixos.org)
[![Docs](https://img.shields.io/badge/Docs-Interactive_Portal-cyan)](https://deepwatrcreatur.github.io/nix-router-optimized/)

> **A typed, topology-driven declarative router framework for NixOS.**  
> Deterministic edge networking, dual-node HA failover, zone security, and line-rate forwarding.

---

## Welcome to Declarative Edge Networking

Tired of click-and-pray web GUIs with opaque XML backups? Tired of maintaining fragile bash scripts for `iptables` and `dhcpd` that drift across reboots?

**`nix-router-optimized`** transforms standard x86 and ARM hardware into a carrier-grade edge router using the full power of NixOS. You define your physical links, IP subnets, and security zones as **strict, typed Nix expressions**; the framework deterministically derives your `nftables` firewall rules, Kea DHCP pools, Technitium/Unbound DNS resolvers, and hardware offload parameters.

Every deployment produces an immutable, bit-identical NixOS system generation that can be verified at build time and rolled back instantly if an update misbehaves.

---

## The 4-Stage Declarative Pipeline

Rather than acting as a black-box appliance, the framework operates on a deterministic 4-stage pipeline:

```
Typed Topology  ──▶  Derived Config  ──▶  Immutable Deploy  ──▶  Measurable Perf
  (Strict Nix types,    (nftables, Kea pools,   (Bit-identical            (Zero-regression
   eval assertions)      Technitium DNS, CAKE)   deploy-rs rollbacks)      flowtable & routerctl)
```

1. **Typed Topology**: Interfaces, links, subnets, and VLANs are modeled as typed Nix options. Evaluation-time assertions catch subnet collisions, MTU mismatches, and pool overlaps **before compilation**.
2. **Derived Config**: Netfilter firewall trees (`nftables`), DHCPv4/v6 pools (`Kea`), DNS zones (`Technitium`), and smart queue management (`CAKE`) compile deterministically from your topology.
3. **Immutable Deploy**: Generates reproducible NixOS closures. Deployed via `deploy-rs` with automatic rollback if network connectivity is interrupted.
4. **Measurable Performance**: Driver negotiation, ring buffer sizing, FastTrack flowtables, and multi-queue SMP IRQ affinity deliver line-rate forwarding with structured diagnostic validation via `routerctl`.

---

## What's New & Active Development

### Router Failover & Dual-Node HA (Actively In Progress)
High Availability (HA) failover is **actively being implemented and validated on reference homelab hardware** (`router` VM with Intel 2.5G `igc` + `elitedesk` bare-metal with Intel 10G SFP+ `ixgbe`), rather than existing as a distant roadmap item:

* **Available Today**:
  * **Delayed Fail-Back**: `services.router-ha.preemptDelay` allows a recovered higher-priority node to wait as BACKUP before reclaiming the VIP, preventing failover oscillation.
  * **Secondary Technitium DNS Replication**: `services.router-technitium.zoneReplication` keeps the primary's Technitium zones, including dynamic DDNS records, synchronized on standby nodes via TSIG-signed AXFR/IXFR and NOTIFY.
  * **Golden MAC ISP Modem Cloning**: Clones the ISP-expected MAC address onto the active master node, allowing two routers to share a single dynamic lease over an unmanaged switch.
* **Actively In Progress**:
  * Automatic promotion of replicated Technitium zones to Primary on MASTER, and demotion back to Secondary on BACKUP.
  * Integration of netfilter connection tracking synchronization (`router-conntrackd`) to preserve active TCP/UDP sessions across failover.
  * Non-disruptive networkd reconfiguration (`networkctl reconfigure`) replacing daemon restarts.
* **Honest Operational Boundary**:
  * DHCP currently operates as **single-active with manual promotion** ([`docs/router-dhcp-single-active.md`](docs/router-dhcp-single-active.md)) to prevent lease contention.

---

## Feature Highlights

- ⚡ **Line-Rate FastTrack**: Netfilter flowtables bypass connection tracking for established flows, delivering 20-40% higher throughput and 50% lower CPU usage.
- 🔄 **Automated High Availability**: Keepalived (VRRP, RFC 5798), floating VIPs, preemption delays, and Golden MAC spoofing.
- 🛡️ **Declarative Zone Security**: High-level cross-zone policy matrix (`wan`, `lan`, `iot`, `guest`, `dmz`) compiled into atomic `nftables` chains with egress bogon filtering and Geo-IP blocking.
- 🌐 **IPv6-First & Transition Ready**: DHCPv6 Prefix Delegation (/56), stateless NAT64 (Tayga), DNS64 (Unbound), RFC 6296 NPTv6, and experimental CLAT.
- 🎯 **Enterprise DHCP & DNS**: ISC Kea DHCPv4/v6 with RFC 2136/TSIG dynamic DNS, coupled with Technitium DNS blocklists (Hagezi, OISD).
- 🍰 **Bufferbloat Elimination**: CAKE and fq_codel Smart Queue Management (SQM) for latency-sensitive gaming, voice, and streaming.
- 🧩 **Resource Slice Isolation**: Systemd resource hierarchy (`router-core.slice`, `router-observability.slice`, `router-applications.slice`) preventing telemetry agents from starving packet forwarding.
- 📊 **Edge Observability**: Real-time web dashboard (port 8888), Grafana dashboards, Netdata, and custom `routerctl` CLI inspection.

---

## Why Linux & NixOS? (Comparison with FreeBSD & OPNsense)

Operators comparing DIY routers often ask whether a FreeBSD appliance like OPNsense or pfSense is preferable:

* **High Availability & State Sync**: Keepalived (VRRP) is the direct equivalent of CARP; `conntrackd` (FTFW mode) is the direct equivalent of `pfsync`. Both ensure floating VIP election and stateful session survival.
* **Forwarding Performance**: Linux `nftables` with FastTrack flowtables offloads established flows for line-rate forwarding at low CPU utilization. Furthermore, Linux supports **eBPF / XDP** for kernel-bypass packet filtering inside NIC ring buffers—capabilities FreeBSD lacks.
* **Declarative Fleet GitOps vs. Imperative Web UI**: Rather than managing a single appliance via PHP web forms and mutable XML files (`config.xml`), `nix-router-optimized` treats the router as code within an immutable, bit-reproducible NixOS fleet with atomic GRUB generation rollbacks and compile-time topology validation.

👉 Read the full technical comparison: **[`docs/FREEBSD-OPNSENSE-COMPARISON.md`](docs/FREEBSD-OPNSENSE-COMPARISON.md)**.

---

## Quick Start (60 Seconds)

Add `router-optimized` to your `flake.nix` and import the core modules:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    router-optimized.url = "github:deepwatrcreatur/nix-router-optimized";
  };

  outputs = { self, nixpkgs, router-optimized }: {
    nixosConfigurations.gateway = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        router-optimized.nixosModules.router-networking
        router-optimized.nixosModules.router-dhcp
        router-optimized.nixosModules.router-dns-service
        router-optimized.nixosModules.router-firewall
        router-optimized.nixosModules.router-optimizations
        {
          # 1. Interface and Prefix Topology
          services.router-networking = {
            enable = true;
            wan.device = "eth0"; # Your WAN interface
            routedInterfaces.lan = {
              device = "eth1";   # Your LAN interface
              ipv4Address = "192.168.1.1/24";
              dns = [ "192.168.1.1" ];
              ipv6SendRA = true;
            };
          };

          # 2. DHCP & DNS Services
          services.router-dhcp.enable = true;
          services.router-dns-service = {
            enable = true;
            provider = "unbound";
          };

          # 3. Firewall & Performance Optimizations
          services.router-firewall.enable = true;
          services.router-optimizations = {
            enable = true;
            interfaces = {
              wan = { device = "eth0"; role = "wan"; label = "WAN"; bandwidth = "1Gbit"; };
              lan = { device = "eth1"; role = "lan"; label = "LAN"; };
            };
          };
        }
      ];
    };
  };
}
```

---

## Documentation Hub

To keep this README focused and conversational, in-depth documentation and code references have been organized into dedicated guides:

| Guide / Reference | Description |
| :--- | :--- |
| 🌐 **[Interactive Web Documentation](https://deepwatrcreatur.github.io/nix-router-optimized/)** | Visual network topology maps, failover sequence diagrams, and tabbed code walkthroughs. |
| 📖 **[`docs/MODULES.md`](docs/MODULES.md)** | Exhaustive reference guide for all 38+ modules with option schemas and defaults. |
| 🍳 **[`docs/RECIPES.md`](docs/RECIPES.md)** | Real-world copyable recipes: PPPoE, Caddy HTTPS, Technitium blocklists, secondary log storage, and WARP routing. |
| 🚀 **[`docs/PERFORMANCE-TUNING.md`](docs/PERFORMANCE-TUNING.md)** | Deep dive into FastTrack flowtables, NIC driver negotiation (TSO/GSO/GRO), CAKE SQM, and multi-queue IRQ affinity. |
| 🛡️ **[`docs/FREEBSD-OPNSENSE-COMPARISON.md`](docs/FREEBSD-OPNSENSE-COMPARISON.md)** | Architectural mapping of Linux/NixOS vs. FreeBSD/OPNsense (CARP vs VRRP, pfsync vs conntrackd, pf vs FastTrack/XDP). |
| 🔬 **[`docs/ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md`](docs/ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md)** | Comprehensive ecosystem survey, homelab consumer analysis (`router` & `elitedesk`), secrets paradox, and future roadmap. |
| 📋 **[`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md)** | Verified hardware and driver matrix across Core (Tier 1), SBC (Tier 2), and Budget (Tier 3) hardware. |
| 🚦 **[`docs/work-items/README.md`](docs/work-items/README.md)** | Authoritative ranked execution queue and onboarding runbooks for developers and coding agents. |

---

## Platform Compatibility

The framework is verified across multiple hardware tiers:
- **Tier 1 (Core)**: Intel I225/I226 (2.5G `igc`), Intel X520/X540/X550 (10G `ixgbe`), Intel I350 (1G `igb`).
- **Tier 2 (SBC)**: NanoPi R4S/R5S (Rockchip `rk3568`/`rk3588`), Raspberry Pi 4/5 (Broadcom).
- **Tier 3 (Budget)**: Realtek RTL8125/RTL8111 (`r8169`), Mellanox ConnectX-3/4 (`mlx4`/`mlx5`).

See [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) for full driver validation notes.

---

## Contributing & License

Contributions, bug reports, and hardware validation results are welcome! Please test configurations against `nix flake check` before submitting pull requests.

Released under the [MIT License](LICENSE).
