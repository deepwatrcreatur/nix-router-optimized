# DHCP Server Selection Guide

The `nix-router-optimized` flake provides multiple ways to serve DHCP to your LAN clients. This guide helps you choose the right one based on your performance, high-availability, and complexity needs.

## Quick Comparison

| Feature | `services.router-dhcp` | `services.router-kea` | `services.router-technitium` |
| --- | --- | --- | --- |
| **Backend** | `systemd-networkd` | ISC Kea 3.x | Technitium DNS/DHCP |
| **HA / VRRP** | ❌ None | ⚠️ Advanced / topology-sensitive | ⚠️ Manual Sync |
| **Performance** | ✅ Extreme (Kernel-integrated) | ✅ High (Carrier-grade) | ⚠️ Moderate (.NET) |
| **Complexity** | ✅ Very Low | ❌ High | ✅ Low |
| **Dynamic DNS**| ❌ No | ✅ Robust (RFC 2136) | ✅ Integrated |

---

## 1. `services.router-dhcp` (The Simple Choice)
Best for single-router setups or simple labs where HA is not required.

- **Pros:** Zero configuration; extremely fast; integrated with `systemd-networkd`.
- **Cons:** No High Availability support; no Dynamic DNS registration.
- **Option 108 stance:** Not supported declaratively. Use ordinary dual-stack DHCP here unless you are deliberately building an IPv6-mostly path with a backend that supports RFC 8925 explicitly. If you insist on experimenting anyway, the only honest path is a manual `extraDhcpServerConfig` override against systemd-networkd, not a supported repo feature.
- **Usage:**
  ```nix
  services.router-dhcp.enable = true;
  ```

## 2. `services.router-kea` (The Advanced DHCP/DDNS Choice)
Best for advanced DHCP/DDNS deployments, and only for HA topologies where the
operator is willing to validate the exact transport and ownership model.

- **Pros:** Strong Dynamic DNS support via `kea-dhcp-ddns`; bounded declarative HA
  primitives exist for operators who really need them.
- **Cons:** **High technical sensitivity.** Requires careful socket, interface,
  and ownership configuration. Do not treat “Kea supports HA” as proof that
  your reference pair has safe automatic DHCP failover.
- **Critical Guardrails (Learned from Incident 2026-04-23):**
    - **Raw Sockets:** Default and recommended. Do NOT use address-qualified interfaces (e.g., `eth0/10.0.0.1`) as Kea 3.x will fail to poll for broadcasts.
    - **HA Outbound:** Always use `outboundInterface = "use-routing"` in HA/VRRP setups to ensure the kernel correctly delivers replies.
- **Reference pair boundary:** the current project-maintained router pair is
  documented as **single-active DHCP with manual promotion**, not active Kea HA
  service. See [`router-dhcp-single-active.md`](./router-dhcp-single-active.md).
- **Usage:**
  ```nix
  services.router-kea.enable = true;
  services.router-kea.dhcp4.ha.enable = true;
  ```

## 3. `services.router-technitium` (The All-in-One Choice)
Best for users who want a unified web UI for DNS and DHCP.

- **Pros:** Excellent Web UI; easy to manage reservations.
- **Cons:** High Availability is manual/fragile compared to Kea.
- **Option 108 stance:** Not supported as a first-class declarative feature today. Do not assume NAT64/DNS64 means Technitium DHCP should start telling clients to prefer IPv6-only service automatically, and do not expect the current scope-sync/API layer to manage option `108` declaratively.
- **Usage:**
  ```nix
  services.router-dns-service.provider = "technitium";
  ```

---

## DHCP Option 108 (`IPv6-Only Preferred`)

RFC 8925 option `108` is an advanced DHCPv4 hint for **IPv6-mostly / IPv4-on-demand**
LANs. It tells compatible clients that they may avoid taking or keeping an IPv4
lease for a bounded period (`V6ONLY_WAIT`) while preferring an IPv6-only path.

### Opt-In Prerequisites & Safety Guardrails

- **Declarative Opt-In (`enable = false;` default):** Option 108 is strictly an advanced opt-in feature. It is `false` by default across all flake DHCP modules.
- **Client Impact Warning:** When enabled, compliant clients (such as macOS and Android) will drop or forgo their IPv4 address leases. On a standard dual-stack network without active NAT64/DNS64, this will cause clients to immediately lose connectivity to IPv4-only WAN destinations.
- **Enforced Module Safety Assertions:** To protect dual-stack networks, NixOS module assertions enforce that Option 108 can only be enabled when NAT64 and DNS64 are active:
  - `services.router-kea.dhcp4.ipv6OnlyPreferred.enable = true;` strictly requires:
    - `services.router-nat64.enable = true;`
    - `services.router-dns64.enable = true;`
  - Evaluating `ipv6OnlyPreferred.enable = true;` without both active services will fail Nix evaluation with an explicit safety message.
- **CLAT Distinction:** Option 108 is **not** a substitute for CLAT (`router-clat`). NAT64/DNS64 plus option `108` can help IPv6-capable clients prefer IPv6-only service, but they do not provide client-side socket translation for legacy IPv4-only application binaries.

Backend stance:

- `services.router-kea`: supported first-class with declarative guardrails (`services.router-kea.dhcp4.ipv6OnlyPreferred.enable`)
- `services.router-dhcp`: unsupported declaratively (`enable = false;` default; evaluation assertion enforces disabled state)
- `services.router-technitium`: unsupported declaratively in current sync model (`enable = false;` default; evaluation assertion enforces disabled state)

If you are serving a normal dual-stack LAN, do not enable option `108`. The
safe default remains ordinary DHCPv4 service plus IPv6 alongside it.

---

## Stateful DHCPv6 Host Registration Warning & SLAAC + mDNS Recommendation

Stateful DHCPv6 for LAN host DNS registration (DDNS) is **disabled and strongly discouraged by default** in `nix-router-optimized`.

### Rationale: Client Incompatibilities

Relying on stateful DHCPv6 for local DNS hostname registration is fundamentally broken across modern mobile and IoT client operating systems:

- **Android:** Android OS explicitly refuses to implement stateful DHCPv6 (M-flag) by design. If stateful DHCPv6 is required for IP assignment or host registration, Android devices will fail to acquire IPv6 addresses or register in DNS.
- **iOS & macOS:** Apple operating systems prioritize SLAAC with Privacy Extensions (RFC 8981). They do not reliably trigger stateful DHCPv6 DDNS updates.
- **IoT / Embedded Devices:** Many smart home devices and embedded Linux clients support SLAAC only.

Attempting to enforce stateful DHCPv6 DDNS registration results in unassigned, partially configured, or unresolvable mobile and IoT devices on the LAN.

### Recommended Zero-Config Path: SLAAC + mDNS

The maintainer-sanctioned approach for LAN host resolution is:
1. **SLAAC (Stateless Address Autoconfiguration):** Use Router Advertisements (`services.router-networking` / `systemd-networkd`) to distribute IPv6 prefixes (both GUA for internet routing and ULA `fd00::/8` for stable internal host addressing).
2. **mDNS (`systemd-resolved` / Avahi):** Use Multicast DNS (`.local` hostname resolution) or client-initiated RFC 2136 dynamic updates for local host discovery.

### Example Configuration Stanzas

#### Router Side: Avahi mDNS Reflector (`nix-router-optimized`)
To reflect mDNS packets across isolated LAN/VLAN subnets on the router:

```nix
services.router-mdns = {
  enable = true;
  allowInterfaces = [ "lan" "iot" ]; # null to enable on all non-loopback interfaces
  ipv4 = true;
  ipv6 = true;
};
```

#### Linux Client: `systemd-resolved` Enablement
On Linux clients running `systemd-resolved` (e.g. NixOS clients):

```nix
# NixOS client configuration
services.resolved = {
  enable = true;
  extraConfig = ''
    MulticastDNS=yes
  '';
};
```

Or in standard `systemd-networkd` per-interface network files (`/etc/systemd/network/50-lan.network`):

```ini
[Network]
MulticastDNS=yes
```

#### macOS / iOS / Windows Clients
- **macOS & iOS:** Bonjour (mDNS) is enabled natively by default. Devices respond to `<hostname>.local`.
- **Windows 10/11:** mDNS resolution is enabled natively by default in the LLMNR/mDNS client stack for `.local` queries.

---

## Technical Lessons from the 2026-04-23 Regression
During a major HA transition, we identified that **Kea 3.x is highly sensitive to Linux socket semantics.** 

1. **The Polling Bug:** If you bind Kea to a specific interface IP in `raw` mode, the Linux Packet Filter (LPF) may fail to register the socket for polling, making the server "blind" to broadcasts from new clients. **Always use bare interface names.**
2. **The HA Mask:** Kea HA in `READY` or `WAITING` states will read packets but silently drop them. If your clients aren't getting IPs, check your HA convergence before debugging the socket layer.

