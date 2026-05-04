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
- **Usage:**
  ```nix
  services.router-dns-service.provider = "technitium";
  ```

---

## Technical Lessons from the 2026-04-23 Regression
During a major HA transition, we identified that **Kea 3.x is highly sensitive to Linux socket semantics.** 

1. **The Polling Bug:** If you bind Kea to a specific interface IP in `raw` mode, the Linux Packet Filter (LPF) may fail to register the socket for polling, making the server "blind" to broadcasts from new clients. **Always use bare interface names.**
2. **The HA Mask:** Kea HA in `READY` or `WAITING` states will read packets but silently drop them. If your clients aren't getting IPs, check your HA convergence before debugging the socket layer.
