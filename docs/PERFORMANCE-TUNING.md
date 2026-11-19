# NixOS Router Framework — Performance Tuning & Hardware Offload

This guide explains the optimization pipeline, kernel parameters, and hardware negotiation mechanisms used in `nix-router-optimized`.

---

## 1. FastTrack / Netfilter Flowtable Offloading

In standard Linux routing, every single packet traverses the entire Netfilter rule tree (`prerouting`, `forward`, `postrouting`), evaluating interface sets, connection tracking states, bogon lists, and NAT tables.

`nix-router-optimized` implements **Netfilter Flowtables** (inspired by MikroTik RouterOS FastTrack):
- Once a connection enters the `ESTABLISHED` state, its 5-tuple is registered in an in-kernel flowtable (`flow add @ft`).
- Subsequent packets in that flow bypass the standard firewall chains completely and are passed directly to the egress interface driver.
- **Results**: 20-40% higher throughput on multi-gigabit connections, with CPU usage dropping by over 50%.

### VoIP / SIP Friendly Bypass
Flowtables can occasionally interfere with SIP/RTP media streams that negotiate dynamic RTP port ranges. To keep VoIP crystal clear without disabling flow offload globally:

```nix
services.router-firewall = {
  enable = true;
  flowtable.sipFriendly.enable = true; # Excludes ports 5060, 5061, and UDP 10000-20000
};
```

---

## 2. Driver Offload Negotiation & NIC Pre-Sets

Managed automatically via `services.router-optimizations`:

### The LRO Hazard for Routers
While **Large Receive Offload (LRO)** increases throughput on end-host servers by aggregating multiple TCP packets into a single jumbo frame, **LRO must be disabled on forwarding routers**. When an LRO-aggregated packet exceeds the Maximum Transmission Unit (MTU) of the egress interface, the router must re-fragment or drop the packet, breaking TCP Path MTU Discovery (PMTUD).

`router-optimizations` automatically enforces:
- **TSO (TCP Segmentation Offload)**: Enabled
- **GSO (Generic Segmentation Offload)**: Enabled
- **GRO (Generic Receive Offload)**: Enabled
- **LRO (Large Receive Offload)**: **Strictly Disabled**

### Dynamic Ring Buffer Negotiation
The optimization service queries `/sys/class/net/<iface>` and `ethtool -g` to detect hardware limits, expanding RX/TX ring buffers to hardware maximums (e.g. 2048/4096 on Intel `igc` and `ixgbe` controllers) to prevent packet drops under micro-bursts.

---

## 3. Multi-Queue SMP IRQ Affinity & CPU Pinning

On multi-gigabit network cards:
- **Intel I225/I226 (2.5 Gbps, `igc`)**: 4 hardware queues.
- **Intel X520-2 (10 Gbps SFP+, `ixgbe`)**: Up to 64 MSI-X hardware queues.

By default, Linux often routes all interrupt vectors to **CPU Core 0**, causing Core 0 to saturate at 100% in `ksoftirqd` while cores 1-3 sit idle.

`router-optimizations` configures:
1. **MSI-X IRQ Distribution**: Round-robin assignment of queue interrupts across available CPU cores via `/proc/irq/<irq>/smp_affinity`.
2. **Receive Packet Steering (RPS)**: Configures `/sys/class/net/<iface>/queues/rx-*/rps_cpus` bitmask so packet processing scales across all CPU cores when single-queue limits are reached.
3. **Transmit Packet Steering (XPS)**: Pins transmission queues to matching CPU cores to maintain cache locality.

---

## 4. Smart Queue Management (CAKE / FQ-CoDel)

To eliminate **bufferbloat** (high latency when the uplink is saturated by cloud backups, game updates, or streaming):

```nix
services.router-sqm = {
  enable = true;
  interfaces = [
    {
      device = "eth0";
      bandwidthEgress = "950mbit"; # 95% of line rate
      bandwidthIngress = "950mbit";
    }
  ];
};
```

CAKE automatically prioritizes small latency-sensitive packets (DNS, TCP ACKs, gaming packets, ICMP) over bulk bulk data streams.

---

## 5. Kernel Sysctl Baselines

Key routing and connection tracking sysctl values pre-configured by the framework:

```nix
boot.kernel.sysctl = {
  # IP Packet Forwarding
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;

  # Conntrack Sizing for High-Capacity Homelabs
  "net.netfilter.nf_conntrack_max" = 262144;
  "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;

  # Bufferbloat & Queue Limits
  "net.core.default_qdisc" = "fq_codel";
  "net.core.somaxconn" = 4096;
  "net.core.netdev_max_backlog" = 10000;

  # TCP Congestion Control
  "net.ipv4.tcp_congestion_control" = "bbr";
  "net.ipv4.tcp_fastopen" = 3;
};
```

---

## 6. Verifying Performance with `routerctl`

The framework includes a standalone diagnostic CLI package (`routerctl` / `router-diag`):

```bash
# Check interface driver features and offload state
routerctl offloads

# Inspect static routing and active flowtable status
routerctl status

# Dump connection tracking statistics
routerctl conntrack
```
