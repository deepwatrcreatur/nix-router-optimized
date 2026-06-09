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

Start with the simplest path that honestly matches your constraints.

## Short Answer

1. **Ordinary dual-stack router:** start with `router-networking`
2. **Native multi-uplink IPv6:** read the PvD / multi-WAN guides first
3. **Stable inside prefix with changing upstreams:** consider `router-nptv6`
4. **IPv6-only clients reaching IPv4-only internet services:** use
   `router-nat64` + `router-dns64`
5. **Legacy IPv4 behavior on an IPv6-capable uplink:** evaluate the experimental
   `router-clat` slice
6. **Routed-prefix / VPS / cloud-style neighbor proxying:** start with static
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

### 2. If you have multiple IPv6 uplinks, prefer native answers first

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

### 3. Use `router-nptv6` when the inside prefix should stay stable

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

### 4. Use NAT64 + DNS64 for IPv6-only clients reaching IPv4-only destinations

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

### 5. Use the experimental `router-clat` slice only for the narrower legacy-IPv4 problem

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

### 6. Treat NDP proxying as a separate tool, not as "more NAT64"

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

## Quick "Which One Am I Probably Looking For?"

| Situation | Likely first stop |
|---|---|
| Normal routed IPv6 on one uplink | `router-networking` |
| Native IPv6 on multiple uplinks | PvD / [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md) |
| Stable inside prefix despite outside prefix churn | `router-nptv6` |
| IPv6-only LAN needs access to IPv4-only internet services | `router-nat64` + `router-dns64` |
| Legacy IPv4 client behavior over an IPv6-capable uplink | `router-clat` |
| Routed-prefix / cloud NDP neighbor proxying | static networkd proxy first, then the NDP proxy boundary doc |

## Related Advanced Topics

- DHCP option `108` (`IPv6-Only Preferred`) is an advanced companion to an
  IPv6-mostly design, not the starting point. See [`DHCP_SELECTION.md`](./DHCP_SELECTION.md).
- Translation backend selection is intentionally narrow today. Tayga is the
  current supported NAT64 backend; future backend work should preserve the
  documented contract. See [`router-translation-backends.md`](./router-translation-backends.md).

## One-Sentence Summary

Start with native routing, then move outward only as needed:
PvD or policy routing for multi-uplink native IPv6, NPTv6 for stable-inside
prefix translation, NAT64/DNS64 for IPv6-only clients reaching IPv4 services,
CLAT for the narrower legacy-IPv4 compatibility problem, and NDP proxying only
for routed-prefix neighbor-discovery topologies.
