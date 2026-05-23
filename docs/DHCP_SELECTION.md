# DHCP Server Selection Guide

The `nix-router-optimized` flake provides multiple ways to serve DHCP to your LAN clients. This guide helps you choose the right one based on your performance, high-availability, and complexity needs.

## Quick Comparison

| Feature | `services.router-dhcp` | `services.router-kea` | `services.router-technitium` |
| --- | --- | --- | --- |
| **Backend** | `systemd-networkd` | ISC Kea 3.x | Technitium DNS/DHCP |
| **HA / VRRP** | ❌ None | ✅ Robust (Load Balancing) | ⚠️ Manual Sync |
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

## 2. `services.router-kea` (The Professional Choice)
Best for High-Availability deployments and enterprise-grade networks.

- **Pros:** Native HA load balancing; robust Dynamic DNS support via `kea-dhcp-ddns`.
- **Cons:** **High technical sensitivity.** Requires careful socket and interface configuration.
- **Critical Guardrails (Learned from Incident 2026-04-23):**
    - **Raw Sockets:** Default and recommended. Do NOT use address-qualified interfaces (e.g., `eth0/10.0.0.1`) as Kea 3.x will fail to poll for broadcasts.
    - **HA Outbound:** Always use `outboundInterface = "use-routing"` in HA/VRRP setups to ensure the kernel correctly delivers replies.
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

This repo's support boundary is intentionally narrow:

- It is **not** a default for ordinary dual-stack LANs.
- It is only appropriate when the operator has a working IPv6-first reachability
  story, typically including `router-nat64` and usually `router-dns64`.
- It is **not** a substitute for CLAT. NAT64/DNS64 plus option `108` can help
  IPv6-capable clients prefer IPv6-only service, but they do not provide the
  same compatibility story as a real CLAT path for legacy IPv4-only behavior.

Backend stance:

- `services.router-kea`: supported first-class with declarative guardrails
- `services.router-dhcp`: unsupported declaratively; manual raw-networkd experiments only
- `services.router-technitium`: unsupported declaratively in the current sync/API model

If you are serving a normal dual-stack LAN, do not enable option `108`. The
safe default remains ordinary DHCPv4 service plus IPv6 alongside it.
## Technical Lessons from the 2026-04-23 Regression
During a major HA transition, we identified that **Kea 3.x is highly sensitive to Linux socket semantics.** 

1. **The Polling Bug:** If you bind Kea to a specific interface IP in `raw` mode, the Linux Packet Filter (LPF) may fail to register the socket for polling, making the server "blind" to broadcasts from new clients. **Always use bare interface names.**
2. **The HA Mask:** Kea HA in `READY` or `WAITING` states will read packets but silently drop them. If your clients aren't getting IPs, check your HA convergence before debugging the socket layer.
