# IPv6 Multi-WAN Decision Guide

## Overview

IPv6 multi-WAN in `nix-router-optimized` is not one magical feature.

It is a **toolbox plus decision ladder** built from several existing pieces:

- native multi-prefix advertisements with PvDs
- source-aware policy-routing hooks
- `router-nptv6`
- `ipv6Masquerade` / NAT66 as a compatibility escape hatch

The right answer depends on your constraints:

- whether clients understand PvDs well
- whether you need stable inside addressing
- how much upstream prefix churn you expect
- whether translation is acceptable

## Quick Decision Ladder

Preferred:
- use native multi-prefix IPv6 with PvDs when your clients support it and you
  want to avoid translation

Advanced:
- use source-aware policy routing when you need more explicit uplink steering
  and can reason carefully about source prefix correctness
- use NPTv6 when you want stable inside prefixes while upstream prefixes churn

Discouraged / escape hatch:
- use NAT66 only when compatibility matters more than architectural purity

## Pattern 1: PvD / Native Multi-Prefix

Best when:

- clients are modern and PvD-aware
- you want the cleanest architecture
- you can expose more than one valid IPv6 path to clients

Tradeoffs:

- client support still varies
- older or simpler clients may ignore the extra metadata
- it does not rescue clients that fundamentally choose the wrong source address

Example shape:

```nix
services.router-networking.routedInterfaces.lan = {
  device = "lan0";
  ipv4Address = "10.10.10.1/24";
  pvds = [
    {
      identifier = "isp.example.com";
      hFlag = false;
    }
    {
      identifier = "vpn.example.com";
      hFlag = true;
      sequenceNumber = 42;
    }
  ];
};
```

Start with [`docs/IPV6-PVD.md`](./IPV6-PVD.md) if this is your preferred path.

## Pattern 2: Source-Aware Policy Routing

Best when:

- you need deterministic routing per interface or traffic class
- you understand the uplink/source pairing constraints
- you can validate that packets sourced from prefix A leave through uplink A

Tradeoffs:

- easy to misconfigure silently
- ingress filtering will punish wrong source/uplink combinations
- should be treated as advanced operator territory, not default convenience

Example shape:

```nix
services.router-networking.routedInterfaces.vpn-lan = {
  device = "lan20";
  ipv4Address = "10.20.0.1/24";
  policyRouting = {
    enable = true;
    table = 200;
    rules = [
      {
        priority = 110;
        table = 200;
        to = "2001:db8:feed::/48";
      }
    ];
  };
};
```

Use this when you want explicit routing logic, not when you simply want a
default safe answer.

## Pattern 3: NPTv6

Best when:

- you want a stable inside prefix
- the outside prefix may change
- translation is acceptable, but stateful NAT66 is not your first choice

Tradeoffs:

- still a translation strategy
- adds operational moving parts when the outside prefix is dynamic
- should be used deliberately, not because PvDs are unfamiliar

Example shape:

```nix
services.router-nptv6 = {
  enable = true;
  rules = [
    {
      internalPrefix = "fd00:10:20::/64";
      externalInterface = "wan0";
      autoDetect = true;
    }
  ];
};
```

This is the best fit when stable-inside addressing matters more than preserving
pure native prefix semantics.

## Pattern 4: NAT66 / ipv6Masquerade

Use only when:

- you need a pragmatic compatibility answer
- upstream conditions are hostile or awkward
- you are consciously choosing simplicity over architectural purity

Tradeoffs:

- least preferred architecture
- obscures native source-prefix behavior instead of teaching clients the right
  path
- useful as an escape hatch, not the first recommendation

Example shape:

```nix
services.router-firewall = {
  enable = true;
  ipv6Masquerade = [ "wg0" ];
};
```

Treat this as "make it work" tooling, not as the repo's ideal IPv6 multi-WAN
story.

## How To Choose

If your clients are modern and you want the cleanest architecture:
- choose PvD / native multi-prefix first

If you need explicit steering and can validate source correctness:
- choose policy routing

If you need stable internal addressing despite outside churn:
- choose NPTv6

If you mainly need compatibility and the cleaner paths are impractical:
- choose NAT66 as the fallback

## Important Boundary

Do not assume the repo's IPv4 `router-mwan` failover story automatically solves
IPv6 multi-WAN.

IPv4 failover is mostly a metric problem.
IPv6 multi-WAN often becomes a source-address correctness problem.

For the current IPv4-first failover boundary, see
[`docs/router-mwan.md`](./router-mwan.md).
