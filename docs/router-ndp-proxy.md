# Router NDP Proxy Boundary

This doc records the current support boundary and first-slice contract for NDP
proxying in `nix-router-optimized`.

The short version is:

- do **not** reach for an NDP daemon automatically
- start with native routing and ordinary router advertisements when they are
  sufficient
- if you only need a few fixed proxy entries, prefer
  `systemd-networkd`'s built-in `IPv6ProxyNDP=` / `IPv6ProxyNDPAddress=` path
- `services.router-ndp-proxy` is now the repo's advanced / opt-in first-class
  dynamic path
- the only backend in scope is `ndppd`
- HA is supported only through an explicit single-active-owner boundary

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
- the bounded `services.router-ndp-proxy` module for the declared first slice

### Current module boundary

- one consumer-facing module: `services.router-ndp-proxy`
- one backend: `ndppd`
- advanced / opt-in positioning rather than default router behavior
- `ndpresponder` remains a deferred later candidate
- `ndproxy` and `ndp-proxy-go` are outside the current flake boundary

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

The currently supported first slice stays concrete and narrow:

- one Linux/NixOS router host
- one upstream interface that receives neighbor traffic
- one or more downstream interfaces that serve the addresses behind the router
- a routed-prefix, VPS, cloud, or equivalent provider topology where upstream
  neighbor replies are required for downstream-served IPv6 addresses

This slice does **not** imply support for:

- arbitrary L2 bridging designs
- generic multi-backend NDP abstraction
- generic multi-upstream behavior
- multi-active HA behavior

## First-Slice Module Surface

The current module exposes a bounded typed surface:

- `services.router-ndp-proxy.enable`
- `services.router-ndp-proxy.upstreamInterface`
- `services.router-ndp-proxy.downstreamInterfaces`
- `services.router-ndp-proxy.prefixes`
- small behavior controls:
  - `routeTtlMs`
  - `proxyTimeoutMs`
  - `cacheTtlMs`
  - `routerAdvertisements`
- HA ownership gate:
  - `ha.singleActiveOwner`

The module intentionally avoids:

- raw `ndppd.conf` passthrough as the primary contract
- exposing `ndpresponder`, `ndproxy`, or `ndp-proxy-go`
- broad dashboard or observability scope in the first PR

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

## Example Configuration

See [`../examples/router-ndp-proxy.nix`](../examples/router-ndp-proxy.nix) for
the smallest supported standalone shape.

Minimal example:

```nix
{
  imports = [
    inputs.router-optimized.nixosModules.router-ndp-proxy
  ];

  services.router-ndp-proxy = {
    enable = true;
    upstreamInterface = "eth0";
    downstreamInterfaces = [ "br-lan" ];

    prefixes = [
      {
        prefix = "2001:db8:100::/64";
        method = "interface";
        downstreamInterface = "br-lan";
      }
      {
        prefix = "2001:db8:101::/64";
        method = "auto";
      }
    ];
  };
}
```

This example is intentionally standalone and non-HA.
If you add HA, the module requires the explicit ownership flag described below.

## HA Ownership Rule

NDP proxying is not exempt from the repo's HA honesty rules.

When `services.router-ha.enable = true`, the module requires:

- `services.router-ndp-proxy.ha.singleActiveOwner = true`

That means:

- the service does **not** auto-start on both nodes
- keepalived starts ndppd on the active node
- keepalived stops ndppd on backup or fault transitions
- ambiguous HA topologies fail at eval time instead of appearing supported

The docs must not imply that VRRP alone makes daemon-backed NDP proxying safe.

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

## Operator Verification

After deployment, verify the running service rather than assuming config
generation means the topology works.

Recommended checks:

1. Confirm the service state:

```bash
systemctl status router-ndp-proxy
```

2. Inspect the rendered config:

```bash
cat /etc/ndppd.conf
```

3. Review recent daemon logs:

```bash
journalctl -u router-ndp-proxy -b
```

4. If HA is enabled, inspect keepalived state and ownership transitions:

```bash
systemctl status keepalived
journalctl -u keepalived -b
```

5. Validate the intended route/interface shape:

```bash
ip -6 route
ip -6 neigh
```

## Practical Recommendation

Use this order:

1. native routing + ordinary RA if possible
2. static `systemd-networkd` NDP proxy entries if the proxied addresses are
   fixed and few
3. use `services.router-ndp-proxy` only if you truly need dynamic NDP proxying
   inside the repo's flake boundary

Do not treat the current module as proof that all NDP tools or all HA shapes
are supported.
