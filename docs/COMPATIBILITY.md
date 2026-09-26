# Platform & Hardware Compatibility Matrix

This document defines the supported hardware tiers, network controller capabilities, and testing guarantees for the NixOS Router Framework.

---

## 1. Support Tiers

| Tier | Architecture | Target Platforms / Drivers | Validation Method | Feature Support Level |
|---|---|---|---|---|
| **Tier 1 (Core - Virtualized)** | `x86_64-linux` | Proxmox VE / KVM (`virtio-net`) | Automated NixOS QEMU VM Tests (`checks.vm-smoke`) | **Full**: Line-rate routing, flowtable FastTrack, zone policies, Kea DHCP, Technitium/Unbound DNS, Keepalived VRRP HA, systemd slices. |
| **Tier 1 (Core - Bare Metal)** | `x86_64-linux` | Intel NICs (`e1000e`, `igb`, `igc`, `ixgbe`, `i40e`) | Hardware Lab Benchmarks | **Full**: CAKE / fq_codel SQM, GRO/TSO, BQL, adaptive rx/tx coalescing, multi-queue RSS, BBR congestion control. |
| **Tier 2 (SBC / Edge)** | `aarch64-linux` | Rockchip RK3588 (NanoPi R6S), Raspberry Pi 5 (`bcmgenet`) | Eval Checks + Manual Release Smoke Testing | **Supported**: Core routing, nftables zones, Kea, CAKE SQM. Offloads dynamically negotiated based on SoC PHY driver limits. |
| **Tier 3 (Budget / Auxiliary)** | `x86_64-linux` | Realtek PCIe/USB (`r8169`, `r8152`, `r8153`, `r8125`) | Community Tested | **Constrained**: TSO/GSO guarded against driver ring watchdog timeouts; single-queue RSS; basic SQM. LRO strictly disabled. |

---

## 2. Hardware Offload Safety Matrix

Forwarding routers operate under different network stack constraints than end-host servers. Forwarding packets with Large Receive Offload (LRO) enabled causes severe packet corruption, payload truncation, and TCP checksum invalidations across forwarded interfaces.

The framework enforces hardware offload safety via `services.router-optimizations`:

| Controller Family | Driver | GRO | TSO / GSO | LRO | BQL | Adaptive Coalescing | Flowtable FastTrack |
|---|---|---|---|---|---|---|---|
| **VirtIO Network** | `virtio_net` | Supported | Supported | **Disabled** (Enforced) | N/A | Host-managed | Supported |
| **Intel 2.5 GbE** | `igc` (i225/i226) | Supported | Supported | **Disabled** (Enforced) | Supported | Supported | Supported |
| **Intel 1 GbE** | `igb` (i210/i350) | Supported | Supported | **Disabled** (Enforced) | Supported | Supported | Supported |
| **Intel 10 GbE** | `ixgbe` / `i40e` | Supported | Supported | **Disabled** (Enforced) | Supported | Supported | Supported |
| **Realtek 2.5/1 GbE**| `r8169` / `r8125` | Supported | Guarded / Off | **Disabled** (Enforced) | Sensitive | Restricted | Supported |
| **Realtek USB 3.0** | `r8152` / `r8153` | Supported | Disabled | **Disabled** (Enforced) | N/A | N/A | Supported |
| **ARM64 Native** | `rk_gmac-dwmac` | Supported | Driver dependent | **Disabled** (Enforced) | Supported | Fixed | Supported |

### Offload Lifecycle States

At runtime, offload parameters transition through a deterministic 4-state lifecycle tracked in `/run/router/nic-offload-status.json` and inspected via `routerctl`:

1. **`supported`**: Capability is physically exposed by the network device driver.
2. **`enabled`**: Capability was configured via `services.router-optimizations.interfaces.<name>.offloads`.
3. **`effective`**: Capability was successfully set in the kernel via `ethtool` / Netlink.
4. **`reason_disabled`**: Explicit diagnostic reason when a capability is disabled (e.g., `LRO disabled for forwarding safety`, `Driver unsupported`).

---

## 3. Resource Isolation & Systemd Slices

To ensure control plane survival during telemetry bursts, logging storms, or memory leaks, production deployments should enable slice isolation via:

```nix
services.router-slices.enable = true;
```

### Slice Boundaries

- **`router-core.slice`**:
  - *Services*: `systemd-networkd`, `nftables`, `kea-dhcp4-server`, `unbound`, `keepalived`
  - *Guarantees*: `OOMScoreAdjust = -900`, `CPUWeight = 1000`. Memory protected against reclamation during high memory pressure.
- **`router-observability.slice`**:
  - *Services*: `ulogd`, `netdata`, `ntopng`
  - *Guarantees*: `MemoryMax = 256M`, `CPUQuota = 30%`. Prevents packet logging spikes or web telemetry from starving packet routing.
- **`router-applications.slice`**:
  - *Services*: `caddy`, `tailscaled`, reverse proxies, administrative overlays
  - *Guarantees*: `MemoryMax = 512M`, `CPUQuota = 50%`.

---

## 4. Minimum Hardware Recommendations

### Lab & Virtualized (Tier 1)
- **CPU**: 2 vCPUs (x86_64 with SSE4.2 / AVX)
- **RAM**: 1 GB RAM (Core routing + Kea + Unbound) or 2 GB RAM (with Observability & Netdata)
- **Storage**: 8 GB virtual disk
- **NICs**: 2x VirtIO network adapters with multi-queue enabled on the hypervisor

### Bare-Metal Production (Tier 1)
- **CPU**: Intel 8th Gen Core i3 / Celeron J4125 / N100 / AMD Ryzen Embedded or newer
- **RAM**: 4 GB DDR4/DDR5
- **Storage**: 16 GB NVMe / SATA SSD
- **NICs**: Dual or Quad Intel i226-V (2.5 GbE) or Intel i210/i350 (1 GbE)

### Edge SBC (Tier 2)
- **SoC**: Rockchip RK3588 / RK3568 (e.g. NanoPi R5S / R6S)
- **RAM**: 2 GB - 4 GB LPDDR4x
- **Storage**: eMMC or high-endurance microSD / NVMe M.2
