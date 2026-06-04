# IPv6 Multi-WAN Guide

If you are not yet sure whether your problem is multi-uplink native IPv6,
translation, NAT64, or NDP proxying, start with
[`router-ipv6-approach-guide.md`](./router-ipv6-approach-guide.md) first.

Last updated: 2026-05-26

## Objective

Help operators choose the right IPv6 multi-WAN pattern in this repo without
guessing from scattered module docs.

This guide presents the current support surface as a **decision ladder**, not
as one magical “IPv6 multi-WAN” feature.

## Short Answer

Use the first pattern that honestly matches your constraints:

1. **Preferred:** PvD / native multi-prefix
2. **Advanced:** source-aware policy routing
3. **Compatibility-oriented but still deliberate:** NPTv6
4. **Discouraged / last resort:** NAT66 (`ipv6Masquerade`)

## Decision Ladder

### Choose PvD / native multi-prefix when:

- your clients are modern and PvD-aware
- you want to avoid translation
- you can tolerate client-support variation
- you want the cleanest long-term IPv6 model

Why it is preferred:

- clients keep real IPv6 prefixes
- you avoid NAT66
- you avoid rewriting prefixes in the router
- it matches the direction of native multi-prefix IPv6 rather than fighting it

Main tradeoff:

- client support is uneven, so the most standards-pure answer is not always the
  most practical answer

### Choose source-aware policy routing when:

- you already know which downstream segment should prefer which uplink
- you can express that policy explicitly
- you do not need stable-inside translation semantics
- you understand that source-prefix correctness still matters

Why it is advanced:

- it gives fine-grained routing control without immediately reaching for
  translation
- but it requires the operator to reason about prefixes, tables, and uplink
  correctness deliberately

Main tradeoff:

- it is easy to produce silent drops if traffic exits a WAN whose prefix does
  not match the chosen source address

### Choose NPTv6 when:

- you want a stable inside prefix
- your external prefix may rotate
- translation is acceptable
- you want something cleaner than stateful NAT66

Why it is useful:

- it decouples internal addressing from external prefix churn
- it fits the repo's current IPv6 multi-WAN guardrails cleanly
- it is often the most practical answer when native multi-prefix support is not
  good enough on the client side

Main tradeoff:

- it is still translation, so it is not the same thing as native multi-prefix
  IPv6

### Choose NAT66 only when:

- you need a compatibility escape hatch
- you cannot rely on PvD behavior
- NPTv6 is not feasible for the path you need
- and the main goal is “make this path work” rather than architectural purity

Why it is last resort:

- it is the bluntest tool in the set
- it hides rather than solves prefix/uplink design issues
- it is useful, but it should not be the first recommendation when a cleaner
  path is available

## Pattern Comparison

| Pattern | Recommendation | Best for | Main downside |
|---|---|---|---|
| PvD / native multi-prefix | Preferred | modern clients, native IPv6 | client support variance |
| Source-aware policy routing | Advanced | controlled segment-by-segment path steering | easy to misconfigure if source-prefix correctness is ignored |
| NPTv6 | Compatibility-oriented but deliberate | stable-inside prefix with changing upstreams | translation complexity |
| NAT66 | Discouraged / escape hatch | “just make this egress path work” scenarios | least clean architecture |

## Example 1: Preferred Native Multi-Prefix With PvD

Use this when you have modern clients and want the cleanest design.

```nix
services.router-networking = {
  enable = true;

  wan = {
    device = "wan0";
    ipv6AcceptRA = true;
  };

  wans.vpn = {
    device = "wg0";
    ipv6AcceptRA = true;
  };

  routedInterfaces.lan = {
    device = "lan0";
    ipv4Address = "10.10.10.1/24";
    dns = [ "10.10.10.1" ];

    pvds = [
      {
        identifier = "isp.example.net";
        hFlag = false;
        sequenceNumber = 1;
      }
      {
        identifier = "vpn.example.net";
        hFlag = true;
        sequenceNumber = 10;
      }
    ];
  };
};
```

Use this when:

- clients can actually consume PvD information
- you want to steer behavior without translation

Do not use this as your only answer when:

- your client fleet largely ignores PvDs

## Example 2: Advanced Source-Aware Policy Routing

Use this when one downstream segment should prefer one uplink and you can own
the routing policy explicitly.

```nix
services.router-networking = {
  enable = true;

  routedInterfaces.streaming = {
    device = "lan20";
    ipv4Address = "10.20.0.1/24";
    dns = [ "10.20.0.1" ];

    policyRouting = {
      enable = true;
      table = 120;
      rules = [
        {
          to = "::/0";
          table = 120;
          priority = 120;
        }
      ];
    };
  };
};
```

Use this when:

- the operator is comfortable owning explicit routing tables and rules
- you want a narrow, deterministic path choice

Important warning:

- policy routing does **not** remove the need for source-prefix correctness
- if clients use addresses from one uplink prefix while packets leave through
  another uplink, upstream ingress filtering can still drop the traffic

## Example 3: Stable-Inside Prefix With NPTv6

Use this when you want stable internal addressing while the external prefix may
change.

```nix
services.router-nptv6 = {
  enable = true;
  rules = [
    {
      internalPrefix = "fd00:1::/64";
      externalInterface = "wan0";
      autoDetect = true;
    }
  ];
};
```

Use this when:

- stable inside addressing matters
- external prefix churn is the main problem
- translation is acceptable, but NAT66 is not your first choice

Why this is often the pragmatic answer:

- it gives the operator a stable inside prefix
- it works well with the repo's IPv6 multi-WAN guardrails
- it is usually a better first translation answer than NAT66

## Example 4: NAT66 Escape Hatch

Use this only when compatibility matters more than architectural neatness.

```nix
services.router-networking = {
  enable = true;

  routedInterfaces.streaming = {
    device = "lan20";
    ipv4Address = "10.20.0.1/24";
    dns = [ "10.20.0.1" ];
    vpnExit = "tailscale0";
    ipv6Masquerade = true;
  };
};
```

Use this when:

- you need a quick compatibility-oriented egress path
- NPTv6 is not practical for the route you need
- you are consciously accepting the tradeoff

Do not describe this as the preferred IPv6 architecture. In this repo it is the
explicit **escape hatch**.

## Which Pattern Should I Use?

Use this quick decision tree:

- If your clients are modern and you want native IPv6: start with PvD.
- If you already know exactly which segment should prefer which uplink: consider
  source-aware policy routing.
- If you need stable inside prefixes across changing upstreams: prefer NPTv6.
- If you mainly need compatibility and the cleaner options do not fit: use
  NAT66, and document that choice honestly.

## Practical Boundary Notes

- `router-mwan` is not a magical IPv6 balancing surface on its own.
- The repo already guards against the highest-risk unguarded case: multiple IPv6
  WANs with no source-address mitigation.
- PvD and NPTv6 are **not** interchangeable:
  - PvD is native multi-prefix signaling
  - NPTv6 is translation for stable-inside addressing
- NAT66 should not be chosen first just because it looks simpler.

## Related Docs

- [`IPV6-PVD.md`](./IPV6-PVD.md) for the repo's PvD support surface
- [`router-nat64-dns64.md`](./router-nat64-dns64.md) for NAT64/DNS64 transition routing
- [`router-translation-backends.md`](./router-translation-backends.md) for NAT64/CLAT backend boundaries
