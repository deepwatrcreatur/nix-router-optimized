# Router HA Ownership Boundary

`services.router-ha` in this repo is intentionally narrower than a general
"promote every service on the backup router" framework.

The current upstream stance is:

- some ownership patterns are supported explicitly
- some services remain consumer policy
- and some combinations are still intentionally blocked or deferred

This note exists so operators do not infer broader service orchestration than
the modules actually claim.

If you want a concrete starting point instead of a boundary note, start with
[`router-ha-pair-guide.md`](./router-ha-pair-guide.md) and
[`examples/router-ha-pair-example.nix`](../examples/router-ha-pair-example.nix).

## Current Upstream Shape

Each service that must run on one node only declares that itself, with a
typed option, and evaluation fails on a pair where the choice is missing.
Most register their units with router-ha and remove them from boot; BGP
keeps `bgpd` running on both nodes and shuts its neighbours down instead.

| Service | Option | On a `router-ha` pair |
|---|---|---|
| WAN | `services.router-ha.wan` | MASTER raises the WAN, others hold it down |
| IPv6 Router Advertisements | `services.router-ha.routerAdvertisements.mode` | required when any networkd network sends RAs |
| DDNS (inadyn) | `services.router-ddns.ha.singleActiveOwner` | required |
| UPnP / NAT-PMP (miniupnpd) | `services.router-upnp.ha.singleActiveOwner` | required |
| Kea DHCP-DDNS (D2) | `services.router-kea.ddns.ha.mode` | required when `ddns.enable` |
| Kea DHCPv4 | `services.router-kea.dhcp4.ha` | Kea HA on both nodes; never single-active |
| Technitium zones | `services.router-technitium.zoneReplication.ha` | zone primary follows the VIP |
| BGP | `services.router-bgp.ha.singleActiveOwner` | required |
| NDP proxy | `services.router-ndp-proxy.ha.singleActiveOwner` | required |

`services.router-ha.singleActiveUnits` stays for consumer units that have no
typed option. router-ha starts the listed units on promotion and stops them
on backup or fault. It does not take them out of boot; do that yourself
(`wantedBy = lib.mkForce [ ];`).

### IPv6 Router Advertisements

When both nodes advertise, clients take either node as their IPv6 default
router. A backup's WAN is down, so the clients that picked it lose IPv6.
`routerAdvertisements.mode` makes the choice explicit:

- `"vrrp-owner"`: only the MASTER advertises itself as a default router.
  The listed networks (by default every `router-networking` routed
  interface with `ipv6SendRA`) keep sending RAs, but their static config
  sets router lifetime 0, which tells clients "not a default router". On
  promotion, `router-ha-ra-owner.service` writes
  `/run/systemd/network/<network>.network.d/90-router-ha-ra.conf` with the
  real lifetime (router-networking's `routerLifetimeSec`, else networkd's
  1800 s, or `routerAdvertisements.masterRouterLifetimeSec.<network>` for
  networks you define yourself) and runs `networkctl reload`; on demotion it
  removes the drop-in.
  networkd restarts RA on the change, sending a final lifetime-0 RA from the
  old state and fresh RAs at once, so clients switch router within seconds.
  A node that lost its LAN link cannot say goodbye; clients stop using it
  through neighbour unreachability detection, and its first BACKUP RA after
  the link returns clears the stale route. The `vm-router-ha-pair` check
  measures this from a LAN client at every transition.
- `"both-nodes"`: keep RAs on both. Only correct when each node has its own
  working IPv6 uplink.

The reload reconfigures the listed links. On reconfigure (and on every
networkd restart) networkd deletes addresses it did not configure, which
includes keepalived's VIP; keepalived then drops to BACKUP. router-ha
therefore sets `KeepConfiguration=static` on the VRRP interface's network
(`services.router-ha.vrrpNetwork`, detected for router-networking routed
interfaces), and `"vrrp-owner"` requires it. The VM check confirms the VIP
survives each handover. Expect a brief IPv6 blip on the LAN at each handover.

To take a node out of service, stop keepalived (`systemctl stop
keepalived`) or lower its priority. Do not use `ip link set <lan> down`: the
demotion's `networkctl reload` reconfigures the link and networkd brings it
back up. A real carrier loss (cable, switch port) is unaffected.

### DDNS and UPnP

`ha.singleActiveOwner = true` takes the units out of boot and registers them:
`inadyn.timer` plus `inadyn.service` for router-ddns (nixpkgs runs inadyn as
a oneshot from a timer, so listing only the service left the backup's timer
running updates), and `miniupnpd.service` for router-upnp. UPnP port mappings
do not move to the new MASTER; clients re-request them.

On promotion `router-ddns-ha-owner.service` clears inadyn's cache before the
first run. inadyn skips the update when its cache matches the WAN address,
so without this a node returning as MASTER would leave the peer's address
published when the two nodes have different public IPs.

Configs that list these units in `singleActiveUnits` by hand still evaluate
(both inadyn units are needed), with a warning to switch to the typed option.

### Kea D2

- `ddns.ha.mode = "single-active"`: D2 runs only on the MASTER. Use it when
  DHCPv4 is also single-active.
- `ddns.ha.mode = "follow-vip"`: D2 runs on both nodes and `serverAddress`
  defaults to the VIP, where the zone primary lives under
  `zoneReplication.ha`. Required with `dhcp4.ha`, because both Kea servers
  hand out leases. `serverAddress` must be the VIP address.
  - Add both nodes' LAN addresses to the zone's
    `services.router-technitium.rfc2136.zones.<zone>.updateNetworkACL`;
    updates arrive from the node's own address, not from loopback.
  - Technitium must listen on the VIP explicitly (put the VIP in
    `services.router-dns-service.serviceListenAddresses`). On a wildcard
    listener it answers from the node's primary LAN address, and Kea drops
    replies whose source is not the address it queried. Evaluation checks
    this when Technitium runs on the same host.

### Shared on both nodes

- `router-ntp` / Chrony, when the deployment wants standby time sync (see
  [NTP Boundary](#ntp-boundary)).
- Passive observability such as Suricata.

### Minimal consumer sketch

```nix
{
  services.router-ha = {
    enable = true;
    role = "master"; # or "backup" per host
    virtualIp = "10.10.10.1/16";
    vrrpInterface = "br-lan";
    routerAdvertisements.mode = "vrrp-owner";
    wan = {
      enable = true;
      interface = "wan0";
      clonedMac = "02:00:00:00:00:01";
    };
  };

  services.router-ddns = {
    enable = true;
    ha.singleActiveOwner = true;
  };
  services.router-upnp = {
    enable = true;
    ha.singleActiveOwner = true;
  };
  services.router-kea.ddns.ha.mode = "follow-vip"; # with dhcp4.ha

  # Shared service example: keep Chrony on both nodes.
  services.router-ntp.enable = true;
}
```

For a copyable two-node layout, use
[`router-ha-pair-guide.md`](./router-ha-pair-guide.md).

## NTP Boundary

`services.router-ntp` is **not** a typed `router-ha` ownership adapter today.

That means upstream does **not** claim that Keepalived transitions should
universally:

- start or stop `chronyd`
- change Chrony serving behavior automatically
- or define a one-size-fits-all ownership model for LAN-facing NTP service

Why this remains consumer-owned:

- Chrony often serves both upstream sync and downstream LAN clients at once
- the right ownership policy can depend on topology and operational intent
- some operators may want NTP serving on both nodes for management stability,
  while others may want strict single-owner service

So the current stance is explicit non-support for a typed upstream adapter, not
an accidental omission.

## What Upstream Does Guarantee

With `services.router-ntp.enable = true`:

- Chrony is configured as the NTP server
- LAN client access can be bounded by `lanSubnets`
- UDP 123 is opened on trusted interfaces when `router-firewall` is present

But `router-ha` does **not** add a Chrony-specific promotion/demotion hook.

## What Consumers Should Do

If a deployment needs LAN-facing NTP to follow an ownership model, the consumer
configuration should express that policy explicitly.

Examples of consumer-owned choices:

- keep Chrony available on both nodes
- gate Chrony behind a promoted-node profile
- couple NTP visibility to a broader active-service layer

The current validated reference deployment uses the **first** of those choices:
Chrony available on both nodes.

What should not be assumed:

- that enabling `router-ha` implies Chrony ownership semantics
- that VRRP transitions automatically define the correct NTP behavior

## Support Boundary Summary

- **Supported upstream:** router NTP service itself
- **Not currently supported upstream:** a typed `router-ha` adapter for NTP
- **Expected policy owner:** consumer config

For risky ownership, WAN, or failover changes, use
[`router-apply-safety.md`](./router-apply-safety.md) as the manual acceptance
and rollback procedure.
