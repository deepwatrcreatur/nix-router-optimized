# router-mwan

## Overview

`services.router-mwan` is a small **health-check and route-metric switching**
service for IPv4-first multi-uplink routers.

It is best understood as:

- prioritized uplink failover
- metric-based preference switching
- a bounded companion to `router-networking` and `router-firewall`

It is **not** a general-purpose load-balancing stack.

## What It Supports Well

- one primary WAN plus one or more secondary WANs
- periodic health checks against a chosen target per uplink
- route metric promotion/demotion when an uplink fails or recovers
- straightforward "prefer WAN A, fall back to WAN B" behavior

This is a useful supportable default for small routers where the operator wants
automatic failover without building a full routing policy engine.

## What It Does Not Promise

Do not read `router-mwan` as:

- aggregate throughput across multiple uplinks
- ECMP-style balancing
- session-preserving failover for existing flows
- state-synchronized HA behavior
- an automatic answer for IPv6 multi-WAN source-correctness

Those are different problems with different operational tradeoffs.

## Recommended Shape

The normal supported shape is:

- a primary WAN with the lower metric
- a secondary WAN with the higher fail metric
- health checks that promote or demote the default route

Example:

```nix
{
  imports = [
    inputs.nix-router-optimized.nixosModules.router-networking
    inputs.nix-router-optimized.nixosModules.router-mwan
  ];

  services.router-networking = {
    enable = true;
    wan.device = "wan0";
    wans.backup = {
      device = "wan1";
      manageWithNetworkd = true;
    };
  };

  services.router-mwan = {
    enable = true;
    checkInterval = 5;
    interfaces = [
      {
        interface = "wan0";
        trackIp = "1.1.1.1";
        primaryMetric = 100;
        failMetric = 2000;
      }
      {
        interface = "wan1";
        trackIp = "9.9.9.9";
        primaryMetric = 200;
        failMetric = 2100;
      }
    ];
  };
}
```

In this shape:

- `wan0` is the preferred uplink while healthy
- `wan1` remains available as a lower-priority fallback
- failure causes metric switching, not bandwidth aggregation

## Relationship To IPv6 Multi-WAN

IPv4 failover is mostly a default-route and metric problem.

IPv6 multi-WAN is often a **source-address correctness** problem:

- a client may select an address from prefix A
- while traffic exits uplink B
- and the upstream drops the packet because the source no longer matches the
  expected provider path

That is why the repo treats IPv6 multi-WAN separately instead of describing
`router-mwan` as a universal multi-WAN layer.

If you are solving IPv6 multi-WAN, start with
[`docs/ipv6-multiwan.md`](./ipv6-multiwan.md).

## When To Reach For Something Else

Consider a different tool or an explicitly advanced design when you need:

- deterministic source-based IPv6 routing
- stable internal IPv6 identity across prefix churn
- translation-based prefix portability
- more than simple preferred-uplink failover

Relevant repo surfaces:

- `router-networking` policy-routing hooks
- [`docs/IPV6-PVD.md`](./IPV6-PVD.md) for native multi-prefix client steering
- `router-nptv6` for stable-inside prefix translation
- `ipv6Masquerade` / NAT66 as an escape hatch rather than the default answer
