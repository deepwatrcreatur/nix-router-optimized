# Router NDP Proxy Boundary

This doc records the current support boundary and first-slice contract for NDP
proxying in `nix-router-optimized`.

The short version is:

- do **not** reach for an NDP daemon automatically
- start with native routing and ordinary router advertisements when they are
  sufficient
- if you only need a few fixed proxy entries, prefer
  `systemd-networkd`'s built-in `IPv6ProxyNDP=` / `IPv6ProxyNDPAddress=` path
- if the repo adds a first-class dynamic path later, `ndppd` is the only honest
  near-term backend candidate
- any future daemon-backed module is advanced / opt-in and must preserve a
  single-active-owner HA boundary

This boundary comes from the archived repo discussion:

- [`discussions/15-ndp-proxy-tool-inclusion-boundary.md`](./discussions/15-ndp-proxy-tool-inclusion-boundary.md)

## What Problem NDP Proxying Actually Solves

NDP proxying is for topologies where the upstream network expects neighbor
responses for addresses that are really being served behind your router.

Typical examples:

- a routed prefix on a VPS or cloud VM
- KVM or bridge setups where the upstream only sees one L2 segment
- provider environments that require neighbor proxy replies for
  downstream-served IPv6 addresses

It is **not** the first answer for:

- ordinary dual-stack home LANs
- NAT64 / DNS64
- CLAT
- generic IPv6 multi-WAN design

If the real problem is native routed IPv6, NAT64, CLAT, or translation, use the
specialized docs for those surfaces instead.

## Current Repo Boundary

The current repo stance is intentionally narrow.

### Supported guidance today

- native routed IPv6 via `router-networking`
- static `systemd-networkd` proxy entries when your topology only needs a small
  fixed set of proxied addresses

### Not yet a shipped first-class module

- a repo-owned dynamic NDP proxy module such as `services.router-ndp-proxy`

### If a module lands later

- it should present one normalized consumer-facing surface
- it should remain advanced / opt-in rather than a default router feature
- `ndppd` is the only honest near-term backend candidate
- it should not broaden into a generic multi-backend NDP toolbox in the first
  PR

## When Static `systemd-networkd` Proxy Entries Are Enough

Prefer static `systemd-networkd` proxy entries when:

- the proxied IPv6 addresses are known ahead of time
- the list is small enough to maintain explicitly
- you do not need dynamic neighbor learning
- the topology is single-router and the static entries are operationally clear

This is the least surprising path because it stays close to the existing
networkd configuration model instead of introducing another daemon.

Use a daemon only when you have a real need for dynamic NDP handling, not
because NDP proxying sounds like the "advanced" IPv6 answer.

## First Supported Dynamic Topology

If the repo adds a daemon-backed first slice, the supported topology should stay
concrete and narrow:

- one Linux/NixOS router host
- one upstream interface that receives the neighbor traffic
- one or more downstream interfaces that serve the addresses behind the router
- a routed-prefix, VPS, cloud, or equivalent provider topology where upstream
  neighbor replies are required for downstream-served IPv6 addresses

This first slice should **not** imply support for:

- arbitrary L2 bridging designs
- automatic topology discovery
- generic multi-upstream behavior
- or multi-active HA behavior

The goal is to support one honest Linux router shape before expanding the
surface.

## First-Slice Module Contract

If the repo adds a first-class dynamic module, the first slice should look like
this:

- one normalized option surface rather than raw daemon-shaped namespaces
- one backend: `ndppd`
- a small typed input model centered on:
  - enable / disable
  - one upstream interface
  - one or more downstream interfaces
  - any bounded prefix or proxy-entry shape needed for deterministic config
- deterministic generated config and a managed systemd service

What the first slice should avoid:

- raw `ndppd.conf` passthrough as the primary contract
- a backend selector for multiple tools on day one
- a promise that every NDP-related daemon is interchangeable

## Explicit Exclusions

The repo should document the named alternatives explicitly rather than leaving
them as implied future parity targets.

### `ndpresponder`

Deferred for now.

Why:

- it has real routed-prefix and VPS use cases
- but it is not currently packaged in nixpkgs here
- and the repo has not yet decided to own that packaging and support burden

### `ndproxy`

Out of scope for the current boundary.

Why:

- the name does not point to one coherent, clearly supportable upstream target
- and exposing it would imply a cleaner support contract than actually exists

### `ndp-proxy-go`

Out of scope for the current boundary.

Why:

- it belongs to a FreeBSD-centered architecture story
- and that does not map cleanly onto this repo's Linux/NixOS router surface

## HA Ownership Rule

NDP proxying is not exempt from the repo's HA honesty rules.

If a future daemon-backed module lands, it must preserve a strict ownership
boundary:

- single-active owner only when HA is present
- no silent dual-active proxy replies for the same proxied addresses
- assertion-driven refusal for ambiguous `router-ha` combinations

The docs must not imply that VRRP alone makes daemon-backed NDP proxying safe.
The later module should follow the same spirit already used in adjacent
HA-sensitive areas: if ownership is ambiguous, the repo should fail at eval time
instead of pretending the topology is supported.

## How This Relates To NAT64 And CLAT

It is easy to confuse these because they all appear in IPv6-heavy deployments,
but they solve different problems:

- **NAT64 + DNS64**: IPv6-only clients reaching IPv4-only destinations
- **CLAT**: legacy IPv4 client behavior on an IPv6-capable uplink
- **NDP proxying**: neighbor discovery for addresses served behind the router

If your problem is "IPv6-only clients need to reach IPv4 websites," read
[`router-nat64-dns64.md`](./router-nat64-dns64.md) instead.

If your problem is "legacy IPv4 behavior still needs to work on an IPv6 uplink,"
read [`DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md).

## Practical Recommendation

Use this order:

1. native routing + ordinary RA if possible
2. static `systemd-networkd` NDP proxy entries if the proxied addresses are
   fixed and few
3. wait for or help implement the bounded `ndppd` path only if you truly need
   dynamic NDP proxying inside the repo's flake boundary

Do not treat the archived discussion as proof that a dynamic NDP proxy module
already exists.
