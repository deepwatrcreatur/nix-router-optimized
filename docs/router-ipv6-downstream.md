# IPv6 on downstream segments

How LAN and VLAN clients get IPv6 from this flake, and why there is no
DHCPv6 server module. Preserving the ISP prefix across an HA failover is a
separate topic (`services.router-ha.wan.sharedDhcpIdentity`, see
[router-ha-pair-guide.md](./router-ha-pair-guide.md)).

## Decision

**Supported model: SLAAC from the ISP's delegated prefix, announced by
systemd-networkd.** No DHCPv6 server and no prefix delegation to downstream
routers for now (router-xm6, 2026-11-21).

## What systemd-networkd provides

| Need | networkd | How this flake uses it |
|---|---|---|
| Get a prefix from the ISP | DHCPv6 client with prefix delegation on the WAN | `router-networking.wan` |
| One /64 per segment from that prefix | `[DHCPPrefixDelegation]` on each downstream link, `SubnetId=` picks which /64 | `routedInterfaces.<name>.dhcpPrefixDelegation` (default on), `ipv6SubnetId` |
| Router address on each segment | `Assign=yes` (EUI-64 from the delegated /64) | default |
| Announce prefix, default route, DNS | RAs with PIO, RDNSS, DNSSL, router lifetime | `ipv6SendRA`, `dns`, `domains`, `routerLifetimeSec` |
| Static or ULA prefixes | `[IPv6Prefix]` | `ipv6Prefix`, `ulaPrefix` |
| Stateful DHCPv6 (addresses or options) | **none**: networkd's DHCP server is IPv4 only | none |
| Delegating prefixes to downstream routers | **none** | none |

Clients therefore form their own addresses (SLAAC, with privacy addresses
where the OS enables them) and learn DNS from RDNSS.

### Stable segment prefixes

Without `ipv6SubnetId`, networkd assigns subnet IDs itself, and a segment's
/64 can move when segments are added or removed. Set an ID per segment so
firewall rules, DNS records and monitoring keep matching:

```nix
services.router-networking.routedInterfaces = {
  lan.ipv6SubnetId = "0x1";   # 2001:db8:100:1::/64 from a 2001:db8:100::/56
  iot.ipv6SubnetId = "0x20";
};
```

The IDs must fit in the delegation (a /56 gives 0x0 to 0xff) and be unique;
evaluation checks uniqueness.

### `prefixDelegationMode = "managed"`

It sets the RA M and O flags, which tell clients to ask a DHCPv6 server.
Nothing in this flake answers, so clients still use SLAAC and some retry
DHCPv6 in the background. Evaluation warns when it is set. Use it only with
a DHCPv6 server you run yourself.

## Why no DHCPv6 server

- Android does not implement DHCPv6 for addresses; SLAAC is the one method
  every client supports.
- Residential delegations are dynamic. A DHCPv6 server (Kea) needs static
  pools, so it would have to be regenerated whenever the ISP prefix changes;
  networkd's RAs follow the delegation automatically.
- Downstream routers that want their own delegation are rare in a home or
  small-office network. A second router can use a ULA or NAT66 on its side,
  or get a routed /64 from a static route.

## Revisit when

- A client must be tracked by DHCPv6 lease or DUID (for example, for
  accounting or fixed IPv6 assignments that SLAAC tokens cannot cover).
- A downstream router needs real prefix delegation.
- The prefix is static (business line), which makes Kea DHCPv6 pools
  practical.

Then the likely shape is Kea DHCPv6 in `router-kea` with pools derived from a
static prefix, with `prefixDelegationMode = "managed"` on the segments it
serves.

## Tested

`vm-router-ipv6-downstream`:
- **ISP:** a simulated ISP delegates a /56.
- **Router:** gives two segments their /64s by subnet ID (0x1 and 0x2).
- **Clients:** each client forms a SLAAC address in its own /64, gets a default route via the router and RDNSS, and reaches the ISP over IPv6. The second segment uses `"managed"` and still works through SLAAC.
