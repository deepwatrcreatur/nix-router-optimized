# Multicast proxying (`router-multicast`)

Forwards IPv4 multicast streams, typically IPTV, from an upstream network to
chosen LAN segments, using [igmpproxy](https://github.com/pali/igmpproxy).
Receivers join groups with IGMP; the router joins upstream on their behalf
and forwards only the groups someone downstream is watching.

```nix
{
  services.router-multicast = {
    enable = true;
    upstream.interface = "wan0.40";   # e.g. the ISP's IPTV VLAN
    downstreams = [ "lan0" ];          # segments with set-top boxes
  };
}
```

## What it configures

- `router-multicast.service` runs igmpproxy with the upstream, the listed
  downstreams and optional group filters (`upstream.allowGroups`,
  `upstream.denyGroups`, `allowGroups`, `denyGroups`).
- Every other interface stays disabled for multicast routing. igmpproxy 0.4
  leaves unlisted interfaces disabled; the module never sets `defaultdown`.
- With `router-firewall`: IGMP is accepted on the upstream and downstreams,
  and `224.0.0.0/4` from the upstream is forwarded to the listed
  downstreams only. Both rules sit in the early hooks, ahead of the WAN
  chains, so they work when the upstream is a WAN-zone VLAN.
- `upstream.sources` (default `0.0.0.0/0`) are the networks multicast may
  come from. igmpproxy otherwise only accepts sources on the upstream's own
  subnet, and IPTV sources are usually remote.

## Reverse path filtering

IPTV sources are usually reachable through the internet WAN, not the IPTV
VLAN, so strict `rp_filter` on the upstream drops the stream.
`looseReversePathFilter` (default on) sets the upstream to 2 (loose) when
the service starts. The kernel uses the larger of `conf.all` and the
interface value, so this also works under `router-security-hardened`, which
sets `all` to 1 (strict). Loose mode still needs *some* route back to the
source, normally the default route.

## Choices and limits

- **Upstream is not assumed to be the WAN.** Many ISPs carry IPTV on its own
  VLAN; set that interface.
- **quickleave** (default on): the router leaves a group upstream as soon as
  the last receiver leaves, so channel changes are fast and unwatched
  channels stop using upstream bandwidth. With several receivers of the
  same group on one segment, the others can see a short gap while igmpproxy
  re-queries. Turn it off if that matters more than upstream bandwidth.
- **IGMPv3 / SSM:** igmpproxy handles IGMPv3 reports as any-source joins.
  Source-specific multicast (SSM, `232.0.0.0/8` with a named source) is not
  proxied as such. Services that require SSM need PIM-SSM routing, which
  this module does not provide.
- **No ISP promises.** IPTV setups vary: VLAN IDs, 802.1p priority, DHCP
  options on the IPTV VLAN, whether IGMPv2 or v3 is expected. Configure the
  upstream interface itself (VLAN, address, routes) with
  `router-networking` or networkd to match your ISP.
- **Not included:** smcroute (static multicast routes between your own
  VLANs) and PIM. Discovery protocols such as SSDP and mDNS are local; use
  reflection (`router-mdns`) for those, not multicast routing.
- IPv4 only (no MLD proxying).

## Tested

`vm-router-multicast`:
- **Setup:** a source on the upstream VLAN streams `239.1.1.1` from a remote address. The router's default route points out another interface and `all.rp_filter` is strict, which is the IPTV-on-a-VLAN case.
- **Results:**
  - The lan receiver joins and gets the stream.
  - A receiver on another VLAN joins and gets nothing.
  - After the lan receiver leaves, the route is withdrawn and the lan link stays silent.

Eval checks live in `tests/router-multicast.nix`.
