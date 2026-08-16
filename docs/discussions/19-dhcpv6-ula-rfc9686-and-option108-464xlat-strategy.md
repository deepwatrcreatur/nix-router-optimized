# Discussion 19: DHCPv6 Host Registration, ULA (RFC 9686), and DHCP Option 108 / 464XLAT Strategy

**Status:** closed  
**Scope:** `nix-router-optimized`  
**Date:** 2026-08-16  

## Why this discussion exists

As IPv6 adoption expands across homelab and dual-router infrastructure (e.g. `router` and `router-backup`), operators face three recurring protocol and architecture decisions regarding LAN configuration:

1. **Host Registration in DNS:** Should the router enable stateful DHCPv6 to assign IPv6 addresses and dynamically register LAN hosts in DNS, or rely on SLAAC and mDNS?
2. **ULA vs. GUA (RFC 9686 / RFC 6724bis):** Should internal LAN hosts be assigned Unique Local Addresses (ULA, `fd00::/8`) alongside Global Unicast Addresses (GUA), and how does RFC 9686 prefix delegation/address selection impact local routing?
3. **DHCP Option 108 (RFC 8925) & 464XLAT (RFC 6877):** When should DHCP Option 108 (`IPv6-Only Preferred`) and 464XLAT (CLAT + NAT64/DNS64) be deployed in `nix-router-optimized`?

This roundtable discussion records the multi-agent deliberation and establishes the official maintainer guidance for `nix-router-optimized`.

## Participation record & Grounding

Following the deliberation protocol outlined in `docs/discussions/README.md`, this round synthesizes positions across the core multi-agent roster:

- **Codex CLI** (Low-level implementation: `systemd-networkd`, Kea, kernel socket mechanics)
- **Gemini CLI** (via `agy`) (User experience & homelab operations)
- **DeepSeek API** (Protocol standards: RFC 8925, RFC 6877, RFC 9686, RFC 6724bis)
- **Copilot / Claude IC synthesis** (Developer experience & integration architecture)

### Grounding files consulted
- `nix-router-optimized/docs/router-ipv6-approach-guide.md`
- `nix-router-optimized/docs/DHCP_SELECTION.md`
- `nix-router-optimized/docs/router-nat64-dns64.md`
- `nix-router-optimized/docs/DECLARATIVE_CLAT.md`
- `nix-router-optimized/docs/discussions/13-ipv6-reliance-in-an-upgraded-homelan.md`

---

## Voice summaries

### Codex CLI

- **Core position:** Stateful DHCPv6 for host DNS registration is fundamentally broken on modern client operating systems. Rely on SLAAC for IP assignment and mDNS/RFC 2136 for host discovery.
- **Key implementation points:**
  - **DHCPv6 Client Fragmentation:** Google Android explicitly hard-codes a refusal to support stateful DHCPv6 (M-flag). iOS and macOS prioritize SLAAC with Privacy Extensions (RFC 8981). Enabling stateful DHCPv6 as a primary DNS registration mechanism leaves Android/IoT devices completely unregistered or without IPv6 addresses.
  - **Option 108 Technical Guardrails:** DHCP Option 108 (RFC 8925) instructs dual-stack clients to forgo IPv4 leases. In `nix-router-optimized`, Option 108 is only supported in `services.router-kea` (`dhcp4` raw socket mode). Enabling Option 108 on a standard dual-stack network without active `router-nat64` + `router-dns64` causes Option 108-compliant clients (macOS/Android) to drop IPv4 and fail to connect to IPv4-only WAN destinations.
- **Verdict:** Do not use stateful DHCPv6 for DNS registration. Keep Option 108 disabled on standard dual-stack LANs.

### Gemini CLI (via `agy`)

- **Core position:** ULA (`fd00::/8`) combined with RFC 9686 Prefix Delegation provides essential stability for homelab inter-service communication when ISP public GUA prefixes rotate.
- **Key homelab points:**
  - **The Dynamic Prefix Problem:** Most consumer ISPs assign dynamic IPv6 Global Unicast Address (GUA) prefixes via DHCPv6-PD that rotate on router reboot or reconnect. If local services (`homeserver`, `attic-cache`, `proxmox`) rely strictly on GUA for internal traffic, internal DNS records and firewall rules break whenever the ISP rotates the prefix.
  - **ULA for Internal Invariants:** Distributing a ULA prefix (`fd00::/8`) via Router Advertisements alongside dynamic GUA ensures internal hosts maintain permanent, non-changing IPv6 addresses for local inter-host traffic.
  - **Local Hostname Resolution:** `systemd-resolved` and Avahi mDNS (`hostname.local`) solve LAN host resolution zero-config across Linux, macOS, and iOS without stateful DHCPv6 overhead.
- **Verdict:** Strongly recommend ULA (`fd00::/8`) for internal stability. Use mDNS for zero-config LAN hostname resolution.

### DeepSeek API

- **Core position:** Protocol standards (RFC 9686 and RFC 6724bis) fix historic ULA precedence traps. 464XLAT and Option 108 are specialized tools for IPv6-mostly segments, not defaults.
- **Key protocol points:**
  - **RFC 9686 & RFC 6724bis:** Historically, RFC 6724 default address selection caused dual-stack hosts to prefer IPv4 over ULA because ULA lacked a default route. RFC 9686 (ULA Prefix Delegation) and RFC 6724bis update host rule tables so ULA is preferred for internal routes while GUA/IPv4 is used for internet egress.
  - **NAT64/DNS64 vs. 464XLAT (CLAT):**
    - `router-nat64` + `router-dns64` translates IPv6-only client traffic reaching IPv4 internet targets.
    - 464XLAT (`router-clat` / RFC 6877) provides client-side translation for legacy IPv4-only socket applications.
    - DHCP Option 108 is the trigger that signals IPv6-mostly capability to clients.
- **Verdict:** RFC 9686 / ULA is standard-compliant and effective. Option 108 and 464XLAT must remain opt-in advanced features reserved for dedicated IPv6-mostly segments.

### Copilot / Claude IC Synthesis

- **Core position:** Reconcile protocol recommendations into actionable maintainer guardrails for `nix-router-optimized` and `unified-nix-configuration`.
- **Key consensus points:**
  - **DNS & Host Discovery:** Reject stateful DHCPv6 for DNS registration. Recommend SLAAC + mDNS (`systemd-resolved` / `avahi-daemon`) for LAN host discovery.
  - **Internal Addressing:** Endorse ULA (`fd00::/8`) alongside GUA. Use `router-nptv6` if outside GUA prefix rotation requires stateless 1:1 translation.
  - **IPv6-Only Transition Tools:** Keep DHCP Option 108 and 464XLAT disabled by default. Enable them only on dedicated experimental IPv6-mostly subnets backed by Tayga/Unbound (`router-nat64` / `router-dns64`).

---

## Convergence

The round converged on three direct protocol decisions:

### 1. Host DNS Registration & mDNS vs. DHCPv6
- **Decision:** **Do NOT rely on stateful DHCPv6 for host DNS registration.**
- **Reasoning:** Android, iOS, and IoT clients do not support or prefer stateful DHCPv6 DDNS registration.
- **Recommendation:** Deploy **SLAAC** (Stateless Address Autoconfiguration) via Router Advertisements for IPv6 host address generation, and use **mDNS** (`systemd-resolved` / Avahi) or RFC 2136 client registration for local `.local` / LAN hostname resolution.

### 2. ULA Addresses & RFC 9686
- **Decision:** **YES, configure ULA (`fd00::/8`) alongside GUA for LAN hosts.**
- **Reasoning:** Dynamic ISP IPv6 prefix delegation (GUA) changes periodically, breaking internal host-to-host links. ULA provides permanent, stable internal IPv6 addresses for homelab infrastructure (`homeserver`, `attic-cache`, `proxmox`, etc.).
- **Protocol Alignment:** Modern host operating systems complying with RFC 9686 / RFC 6724bis properly prioritize ULA for internal traffic without degrading GUA internet egress.

### 3. DHCP Option 108 & 464XLAT (RFC 6877 / RFC 8925)
- **Decision:** **Do NOT enable Option 108 or 464XLAT on standard dual-stack LANs.**
- **Reasoning:** Option 108 (`IPv6-Only Preferred`) causes compliant clients (macOS, Android) to drop IPv4 leases. If NAT64/DNS64 is not running, clients will lose access to IPv4-only internet servers.
- **Scope:** Option 108 and `router-clat` remain advanced, opt-in features reserved exclusively for dedicated IPv6-mostly lab/test segments running `router-nat64` + `router-dns64`.

---

## Maintained line

The maintained line after this round is:

- **LAN Address Assignment:** Use SLAAC + RA for global IPv6 (GUA) and local IPv6 (ULA).
- **LAN Host Name Resolution:** Use mDNS (`systemd-resolved` / Avahi) for zero-configuration LAN host discovery; do not deploy stateful DHCPv6.
- **ULA Strategy:** Enable ULA (`fd00::/8`) for all internal LAN segments to guarantee static inter-host connectivity across ISP prefix rotations.
- **Transition Options:** Keep DHCP Option 108 and 464XLAT disabled on dual-stack networks.

---

## Bottom line

1. **Stateful DHCPv6 for DNS registration:** Not recommended due to Android/iOS client incompatibilities. Use SLAAC + mDNS instead.
2. **ULA (RFC 9686):** Highly recommended alongside GUA to ensure stable internal IPv6 addresses across ISP prefix rotations.
3. **DHCP Option 108 & 464XLAT:** Keep disabled on standard dual-stack LANs; enable only on explicit IPv6-mostly segments with active NAT64/DNS64.
