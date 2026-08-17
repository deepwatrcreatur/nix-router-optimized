# IPv6 Approach Guide

Use this guide when you know you want "better IPv6" but are not yet sure which
`nix-router-optimized` surface actually matches your topology.

The repo does **not** treat IPv6 as one giant feature flag.
Different modules solve different problems:

- native IPv6 routing and prefix delegation
- multi-prefix / multi-WAN signaling
- prefix translation
- IPv6-only client reachability to IPv4 destinations
- legacy IPv4 compatibility on IPv6-capable uplinks
- routed-prefix NDP proxying
- zero-config LAN host resolution (SLAAC + mDNS)

Start with the simplest path that honestly matches your constraints.

## Short Answer

1. **Ordinary dual-stack router:** start with `router-networking`
2. **Stable LAN IPv6 addressing with dynamic ISP prefixes:** configure SLAAC dual-prefix (GUA + ULA) RAs with RFC 9686 prefix delegation
3. **Native multi-uplink IPv6:** read the PvD / multi-WAN guides first
4. **Stable inside prefix with changing upstreams:** consider `router-nptv6`
5. **IPv6-only clients reaching IPv4-only internet services:** use
   `router-nat64` + `router-dns64`
6. **Legacy IPv4 behavior on an IPv6-capable uplink:** evaluate the experimental
   `router-clat` slice
7. **Routed-prefix / VPS / cloud-style neighbor proxying:** start with static
   NDP proxy entries; treat `ndppd` as the likely future first-class path, not
   as a shipped module today

## Decision Ladder

### 1. Start with native IPv6 first

If your WAN already gives you working IPv6 via RA or DHCPv6-PD, the first thing
to enable is usually just:

- `router-networking` for WAN + routed downstream interfaces
- your normal firewall / DNS / DHCP choices around it

Use this when:

- clients can be dual-stack
- you do not need translation
- you mainly want delegated prefixes, router advertisements, and ordinary routed
  IPv6

Do **not** jump to NAT64, CLAT, or NDP proxying just because IPv6 is involved.
Those are narrower tools for narrower problems.

Relevant docs:

- [`../README.md#router-networking`](../README.md#router-networking)
- [`IPV6-PVD.md`](./IPV6-PVD.md)

### 2. Configure ULA (RFC 9686) alongside GUA for LAN Host Invariants

If your ISP assigns dynamic IPv6 Global Unicast Address (GUA) prefixes via DHCPv6-PD that churn on router reboot or reconnection:

- Assign a **Unique Local Address (ULA, `fd00::/8`)** prefix (e.g. `fd00:acdc:1337:1::/64`) alongside the ISP-delegated GUA prefix on your LAN interfaces.
- Rely on **SLAAC Dual-Prefix Router Advertisements** for host IPv6 configuration.
- RFC 9686 / RFC 6724bis compliance ensures modern operating systems (Linux, macOS, Windows, iOS, Android) select ULA source addresses for local LAN destinations and GUA for internet egress.

#### Why ULA Dual-Prefix over Stateful DHCPv6 or NPTv6?

1. **Dynamic Prefix Rotation Resilience:** Homelab infrastructure (`homeserver`, `attic-cache`, `proxmox`, NAS nodes) maintains permanent, invariant IPv6 addresses (`fd00:...`) even when the public GUA prefix changes.
2. **No Stateful DHCPv6 Requirement:** Android explicitly lacks stateful DHCPv6 (M-flag) client support, and Apple OSes prefer SLAAC RFC 8981 privacy extensions. SLAAC dual-prefix RAs serve all clients universally. Host resolution is handled via zero-config mDNS (`systemd-resolved` / Avahi) or RFC 2136 client registration.
3. **RFC 9686 Address Selection:** Under RFC 9686 (ULA Prefix Delegation) and RFC 6724bis address selection rules, client OSs rank ULA equal to GUA when communicating with internal ULA targets, avoiding IPv4 fallback traps.

Relevant discussions & guides:
- [`discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md`](./discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md)

#### Declarative NixOS Stanzas for Dual-Prefix (GUA + ULA) RAs

##### Option A: Using `services.router-networking` + `systemd-networkd` (Recommended)

In `services.router-networking`, dynamic ISP GUA prefixes are delegated automatically via DHCPv6-PD (`DHCPPrefixDelegation = true`). Adding a static ULA block to `systemd.network.networks` advertises both GUA and ULA prefixes in Router Advertisements:

```nix
{ config, pkgs, ... }:

{
  services.router-networking = {
    enable = true;

    wan = {
      device = "eth0";
      mode = "dhcp";
      prefixDelegationHint = "::/56";
      ipv6AcceptRA = true;
    };

    routedInterfaces.lan = {
      device = "eth1";
      ipv4Address = "10.0.10.1/24";
      role = "lan";
      ipv6Prefix = "::/64";         # ISP-delegated GUA slice via DHCPv6-PD
      prefixDelegationMode = "slaac"; # SLAAC mode (M=0, O=0)
      dns = [ "10.0.10.1" "fd00:acdc:1337:1::1" ];
    };
  };

  # Static ULA address and ULA Router Advertisement prefix
  systemd.network.networks."20-router-lan" = {
    address = [
      "fd00:acdc:1337:1::1/64"
    ];
    ipv6Prefixes = [
      {
        Prefix = "fd00:acdc:1337:1::/64";
        PreferredLifetimeSec = 1800;
        ValidLifetimeSec = 3600;
      }
    ];
  };
}
```

##### Option B: Native `systemd-networkd` Dual-Prefix Configuration

```nix
{ config, pkgs, ... }:

{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # Upstream WAN requesting DHCPv6-PD
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "eth0";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    dhcpV6Config = {
      PrefixDelegationHint = "::/56";
      UseAddress = true;
    };
  };

  # Downstream LAN interface announcing Dual-Prefix SLAAC (GUA + ULA)
  systemd.network.networks."20-lan" = {
    matchConfig.Name = "eth1";
    address = [
      "10.0.10.1/24"
      "fd00:acdc:1337:1::1/64" # Permanent ULA gateway address
    ];

    networkConfig = {
      IPv6SendRA = true;
      DHCPPrefixDelegation = true; # Emits dynamic ISP GUA prefix via RA
      IPv6PrivacyExtensions = "kernel";
    };

    ipv6SendRAConfig = {
      Managed = false;   # SLAAC enabled (M=0)
      OtherInformation = false;
      EmitDNS = true;
    };

    # Emit static ULA prefix in Router Advertisements
    ipv6Prefixes = [
      {
        Prefix = "fd00:acdc:1337:1::/64";
        PreferredLifetimeSec = 1800;
        ValidLifetimeSec = 3600;
      }
    ];
  };
}
```

##### Option C: Declarative RADVD Dual-Prefix Configuration

```nix
{ config, pkgs, ... }:

{
  services.radvd = {
    enable = true;
    config = ''
      interface eth1 {
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        AdvManagedFlag off;
        AdvOtherConfigFlag off;

        # Dynamic ISP GUA prefix delegated from WAN
        prefix ::/64 {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
        };

        # Static ULA prefix for internal homelab invariants (RFC 9686)
        prefix fd00:acdc:1337:1::/64 {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
          AdvPreferredLifetime 1800;
          AdvValidLifetime 3600;
        };
      };
    '';
  };
}
```

### 3. If you have multiple IPv6 uplinks, prefer native answers first

For multi-uplink IPv6, the repo's stance is:

1. preferred: PvD / native multi-prefix
2. advanced: source-aware policy routing
3. compatibility-oriented: NPTv6
4. last resort: NAT66

Use this when:

- you have more than one IPv6-capable uplink
- you are deciding between native multi-prefix signaling and translation

Relevant docs:

- [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md)
- [`IPV6-PVD.md`](./IPV6-PVD.md)

### 4. Use `router-nptv6` when the inside prefix should stay stable

`router-nptv6` is the right tool when your main problem is not “IPv4-only
internet reachability” but rather:

- your outside prefix may rotate
- your inside IPv6 addresses should stay stable
- translation is acceptable
- and you want something cleaner than stateful NAT66

This is often the pragmatic answer for IPv6 multi-WAN or rotating-prefix setups
where native multi-prefix behavior is not sufficient on the client side.

Relevant docs:

- [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md)

### 5. Use NAT64 + DNS64 for IPv6-only clients reaching IPv4-only destinations

This is the right answer when you want an **IPv6-only LAN** but still need those
clients to reach IPv4-only internet services.

Use:

- `router-nat64`
- `router-dns64`
- `router-dns-service.provider = "unbound"`

Use this when:

- clients are IPv6-only or IPv6-mostly
- the WAN has working IPv6
- the missing piece is access to IPv4-only servers on the wider internet

Do **not** treat this as the same thing as CLAT.
NAT64/DNS64 helps IPv6-speaking clients reach IPv4 destinations.
It does not provide the same compatibility story as a true customer-side
translator for legacy IPv4-only application behavior.

Important boundary:

- Technitium is not the DNS64 backend here; Unbound is

Relevant docs:

- [`router-nat64-dns64.md`](./router-nat64-dns64.md)
- [`router-translation-backends.md`](./router-translation-backends.md)

### 6. Use the experimental `router-clat` slice only for the narrower legacy-IPv4 problem

`router-clat` exists for a different problem than plain NAT64.
It is the repo's current experimental answer for:

- legacy IPv4 clients or behaviors
- on an IPv6-capable uplink
- with an intentionally narrow, contract-heavy first slice

Current honesty boundary:

- experimental
- single-router
- non-HA
- not yet a complete router-grade translation/control-plane story

If you only need IPv6-only clients to reach IPv4-only websites, start with
NAT64/DNS64 instead.
Reach for `router-clat` only when the client-side compatibility problem is the
real problem.

Relevant docs:

- [`DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md)
- [`router-translation-backends.md`](./router-translation-backends.md)

### 7. Treat NDP proxying as a separate tool, not as "more NAT64"

NDP proxying solves a different problem again:

- routed prefixes
- VPS / cloud / KVM environments
- upstreams that expect neighbor responses for addresses the router is serving
- topologies where simple downstream RA is not enough

This is **not** the same category as:

- NAT64
- DNS64
- CLAT
- or NPTv6

Current repo stance:

- start with the static `systemd-networkd` `IPv6ProxyNDP=` /
  `IPv6ProxyNDPAddress=` path when static proxy entries are enough
- `services.router-ndp-proxy` is the current advanced / opt-in dynamic path
- `ndppd` is the only backend in scope
- prefer the dedicated NDP proxy doc for the exact support boundary, HA rule,
  and verification steps

Relevant docs:

- [`router-ndp-proxy.md`](./router-ndp-proxy.md)
- [`discussions/15-ndp-proxy-tool-inclusion-boundary.md`](./discussions/15-ndp-proxy-tool-inclusion-boundary.md)

### 8. Prefer SLAAC + mDNS for LAN host discovery over stateful DHCPv6 DDNS

Stateful DHCPv6 host DNS registration is **disabled and strongly discouraged by default** in `nix-router-optimized`.

**Why stateful DHCPv6 DDNS is discouraged:**
- **Android:** Explicitly refuses to support stateful DHCPv6 (M-flag) by design.
- **iOS / macOS:** Prioritize SLAAC with Privacy Extensions (RFC 8981) and do not reliably register via stateful DHCPv6 DDNS.
- **IoT Devices:** Embedded Linux and smart home clients typically support SLAAC only.

Relying on stateful DHCPv6 DDNS leaves mobile and IoT devices unassigned or unregistered in local DNS.

**Recommended zero-config path:**
- **IP Assignment:** SLAAC via Router Advertisements (GUA for internet egress + ULA `fd00::/8` for permanent inter-host addressing).
- **Host Discovery:** mDNS (`services.router-mdns` / `systemd-resolved` / Avahi) for `.local` resolution, or client-initiated RFC 2136 DNS updates.

**Example stanzas:**

- **Router (`nix-router-optimized` Avahi reflector):**
  ```nix
  services.router-mdns = {
    enable = true;
    allowInterfaces = [ "lan" "iot" ]; # null for all non-loopback interfaces
  };
  ```
- **Linux Client (`systemd-resolved` / NixOS):**
  ```nix
  services.resolved = {
    enable = true;
    extraConfig = ''
      MulticastDNS=yes
    '';
  };
  ```
  or in `systemd-networkd` per-interface config:
  ```ini
  [Network]
  MulticastDNS=yes
  ```

Relevant docs:
- [`DHCP_SELECTION.md`](./DHCP_SELECTION.md)
- [`discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md`](./discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md)

## Quick "Which One Am I Probably Looking For?"

| Situation | Likely first stop |
|---|---|
| Normal routed IPv6 on one uplink | `router-networking` |
| Permanent internal IPv6 addressing despite dynamic ISP GUA churn | Dual-Prefix SLAAC (GUA + ULA) / RFC 9686 ([Discussion 19](./discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md)) |
| Native IPv6 on multiple uplinks | PvD / [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md) |
| Stable inside prefix despite outside prefix churn | `router-nptv6` |
| IPv6-only LAN needs access to IPv4-only internet services | `router-nat64` + `router-dns64` |
| Legacy IPv4 client behavior over an IPv6-capable uplink | `router-clat` |
| Routed-prefix / cloud NDP neighbor proxying | static networkd proxy first, then the NDP proxy boundary doc |
| Zero-config LAN hostname discovery | SLAAC + mDNS (`services.router-mdns` / [`DHCP_SELECTION.md`](./DHCP_SELECTION.md)) |

## Related Advanced Topics

- ULA (`fd00::/8`), RFC 9686, and Host Registration strategy: See [`discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md`](./discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md). Stateful DHCPv6 is not recommended due to client OS limitations (Android); SLAAC + mDNS (`systemd-resolved` / Avahi) with dual-prefix RAs is the maintainer standard.
- DHCP option `108` (`IPv6-Only Preferred`) is an advanced companion to an
  IPv6-mostly design, not the starting point. See [`DHCP_SELECTION.md`](./DHCP_SELECTION.md).
- Translation backend selection is intentionally narrow today. Tayga is the
  current supported NAT64 backend; future backend work should preserve the
  documented contract. See [`router-translation-backends.md`](./router-translation-backends.md).

## One-Sentence Summary

Start with native routing, then move outward only as needed:
dual-prefix SLAAC (GUA + ULA per RFC 9686) for stable LAN addressing alongside dynamic ISP prefixes,
PvD or policy routing for multi-uplink native IPv6, NPTv6 for stable-inside
prefix translation, NAT64/DNS64 for IPv6-only clients reaching IPv4 services,
CLAT for the narrower legacy-IPv4 compatibility problem, and NDP proxying only
for routed-prefix neighbor-discovery topologies.
