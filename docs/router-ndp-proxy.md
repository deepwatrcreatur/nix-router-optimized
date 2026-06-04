# Router NDP Proxy Guidance

This doc explains how IPv6 users should think about NDP proxying in
`nix-router-optimized`.

The short version is:

- do **not** reach for an NDP daemon automatically
- start with native routing and ordinary router advertisements when they are
  sufficient
- if you only need a few static proxy entries, prefer
  `systemd-networkd`'s built-in `IPv6ProxyNDP=` / `IPv6ProxyNDPAddress=` path
- treat `ndppd` as the likely future first-class daemon-backed option, but **not
  as a shipped repo module today**

## What Problem NDP Proxying Actually Solves

NDP proxying is for topologies where the upstream network expects neighbor
responses for addresses that really belong behind your router.

Typical examples:

- a routed prefix on a VPS or cloud VM
- KVM / bridge setups where the upstream only sees one L2 segment
- provider environments that effectively require neighbor proxy replies for
  downstream-served IPv6 addresses

It is **not** the first answer for:

- ordinary dual-stack home LANs
- NAT64 / DNS64
- CLAT
- or IPv6 multi-WAN design in general

## Current Repo Boundary

The current repo stance is intentionally narrow.

### Supported guidance now

- native routed IPv6 via `router-networking`
- static `systemd-networkd` proxy entries when your topology only needs a small
  fixed set of proxied addresses

### Not yet a shipped first-class module

- a repo-owned dynamic NDP proxy module such as `services.router-ndp-proxy`

### Current design direction

- if a first-class dynamic module is added, `ndppd` is the only honest
  near-term candidate
- `ndpresponder` remains a deferred later candidate
- `ndproxy` and `ndp-proxy-go` are outside the current flake boundary

That direction comes from the archived repo discussion:

- [`discussions/15-ndp-proxy-tool-inclusion-boundary.md`](./discussions/15-ndp-proxy-tool-inclusion-boundary.md)

## When Static `systemd-networkd` Proxy Entries Are Enough

Start with static proxy entries when:

- the set of proxied IPv6 addresses is small and known ahead of time
- you do not need dynamic neighbor learning
- the topology is single-router and you can describe the addresses explicitly

This is the least surprising path because it stays close to the existing
`systemd-networkd` configuration model instead of introducing another daemon.

Use a daemon only when you have a real need for dynamic NDP handling rather than
because “NDP proxying sounds advanced.”

## When A Dynamic Daemon Becomes Reasonable

A daemon-backed path becomes more reasonable when:

- the proxied address set is dynamic or large
- the operator would otherwise be maintaining a fragile static list
- the environment is a real routed-prefix / cloud / KVM NDP-proxy topology

If the repo eventually lands that surface, the maintained design direction is:

- one normalized module surface
- advanced / opt-in positioning
- `ndppd` as the first backend
- explicit HA ownership assertions rather than silent dual-active behavior

## HA Boundary

NDP proxying is not exempt from the repo's HA honesty rules.

If a future first-class daemon-backed module lands, it should not silently bless
both router nodes answering for the same proxied addresses.

That means:

- single-active-owner semantics must be explicit
- ambiguous HA topologies should fail with assertions rather than appearing
  supported
- and docs should never imply that VRRP alone makes daemon-backed NDP proxying
  safe

## How This Relates To NAT64 And CLAT

It is easy to confuse these because they all appear in IPv6-heavy deployments,
but they solve different problems:

- **NAT64 + DNS64**: IPv6-only clients reaching IPv4-only destinations
- **CLAT**: legacy IPv4 client behavior on an IPv6-capable uplink
- **NDP proxying**: neighbor discovery for addresses served behind the router

If your problem is “IPv6-only clients need to reach IPv4 websites,” read
[`router-nat64-dns64.md`](./router-nat64-dns64.md) instead.

If your problem is “legacy IPv4 behavior still needs to work on an IPv6 uplink,”
read [`DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md).

## Practical Recommendation

Use this order:

1. native routing + ordinary RA if possible
2. static `systemd-networkd` NDP proxy entries if the proxied addresses are
   fixed and few
3. wait for or help implement the bounded `ndppd` path if you truly need dynamic
   NDP proxying inside the repo's flake boundary

Do not treat the archived `ndppd` discussion as proof that the module already
exists.
