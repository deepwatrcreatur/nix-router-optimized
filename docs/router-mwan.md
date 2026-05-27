# Router Multi-WAN

Last updated: 2026-05-26

## What `router-mwan` Is

`router-mwan` is the repo's **prioritized uplink failover** surface.

It does:

- health-check WAN interfaces
- adjust route metrics when a WAN fails or recovers
- support a primary/secondary uplink model
- pair with selected policy-routing or IPv6 mitigation patterns when the
  operator needs them

It does **not** mean generic polished “multi-WAN load balancing.”

## Supported Shape

The standard supported shape is:

- one primary WAN
- one or more backup/prioritized WANs
- health-check driven metric switching

Example:

```nix
services.router-networking = {
  enable = true;

  wan = {
    device = "wan0";
    metric = 100;
  };

  wans.backup = {
    device = "wan1";
    metric = 200;
  };
};

services.router-mwan = {
  enable = true;
  interfaces = [
    {
      interface = "wan0";
      trackIp = "1.1.1.1";
      primaryMetric = 100;
      failMetric = 2000;
    }
    {
      interface = "wan1";
      trackIp = "8.8.8.8";
      primaryMetric = 200;
      failMetric = 2100;
    }
  ];
};
```

This expresses:

- `wan0` is normally preferred
- `wan1` stays available as backup
- health failure raises a route metric instead of promising connection-preserving
  magic

## What It Is Not

Do not read `router-mwan` as a promise of:

- aggregate throughput across uplinks
- ECMP-like balancing
- packet-by-packet or flow-by-flow load spreading
- connection-preserving failover
- state-synchronized HA behavior

If the repo ever grows a more advanced balancing surface, that should be
introduced explicitly as a separate advanced direction rather than silently
widening the meaning of `router-mwan`.

## IPv6 Boundary

IPv4 prioritized failover is the normal `router-mwan` story.

IPv6 multi-WAN is more constrained because source-address correctness matters:

- a client may choose an address from WAN A's prefix
- while the router sends the traffic out WAN B
- and upstream ingress filtering then drops the packets

That is why the repo treats IPv6 multi-WAN as a toolbox and decision ladder,
not as a symmetric “just turn on multi-WAN” feature.

For that boundary, read:

- [`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md)

## Companion Patterns

When operators need more than IPv4 prioritized failover, `router-mwan` can be
paired with:

- source-aware policy routing
- NPTv6
- PvD / native multi-prefix approaches

Those are companion patterns, not proof that `router-mwan` itself is a generic
load-balancing framework.
