# Route-based IPsec (`router-ipsec`)

Site-to-site IPsec with strongSwan (swanctl, IKEv2) where each tunnel is an
**XFRM interface**. The SAs match any traffic (`0.0.0.0/0` both ways) but are
bound to the interface by an `if_id`, so the routing table decides what is
encrypted: static routes, or prefixes learned by BGP over the tunnel. This
is the route-based model (like VTI), without VTI's limits on overlapping
selectors.

```nix
{
  services.router-ipsec = {
    enable = true;
    tunnels.branch = {
      ifId = 10;                          # unique per tunnel
      address = "169.254.10.1/30";        # inside the tunnel
      remote.address = "203.0.113.20";    # peer's public address
      pskFile = "/run/agenix/ipsec-branch-psk";
      routes = [ "10.20.0.0/16" ];        # or learn them with router-bgp
      zone = "vpn";                       # optional router-zones zone
    };
  };
}
```

## What it configures

- A systemd-networkd XFRM netdev (`xfrm-<name>`, `Independent=yes`) with the
  tunnel address and static routes. The module enables systemd-networkd for
  these units if the host does not use it already.
- A swanctl connection with PSK authentication, the IKE/ESP proposals,
  DPD (`dpd_action = restart`), and a child SA bound by `if_id_in/out`.
- Initiators use `start_action = trap|start`: they start at boot, and if the
  peer was not ready (NO_PROPOSAL_CHOSEN while it boots) the next packet
  routed into the tunnel triggers a new attempt. A trap policy with an
  `if_id` only matches traffic through that XFRM interface. Set
  `initiate = false` on a responder-only side, and with `remote.address =
  "%any"`.
- The PSK is read from `pskFile` at service start, hex-encoded into
  `/run/router-ipsec/secrets.conf` (root only), and loaded through a swanctl
  include. It never enters the Nix store. One trailing newline is dropped;
  any other byte, including newlines inside a binary key, is kept.
- Responder-only tunnels (`initiate = false`) clear a dead SA on DPD instead
  of starting an exchange of their own.

## Firewall and zones

With `router-firewall`:

- IKE (UDP 500/4500) and ESP are accepted on the WAN interfaces only (the
  firewall's `wanInterfaces`, or router-optimizations interfaces with role
  `wan`; evaluation fails if there are none), and only from
  `remote.address` when it is an IPv4 literal. A hostname peer
  gets a warning, because the firewall can then not restrict the source.
- Nothing is reachable *through* the tunnel by default. TCP 179 opens on the
  tunnel interface automatically when a `router-bgp` neighbor sits inside
  the tunnel's `address`; add other ports with `allowInputTcpPorts`.
- `zone` puts the XFRM interface into a `router-zones` zone, so forwarding
  between the tunnel and your LANs follows that zone's policies. The zone
  must be defined.

## BGP over the tunnel

Peer with the far side's tunnel address in `router-bgp`, and announce each
side's LANs:

```nix
services.router-bgp = {
  enable = true;
  asn = 65001;
  addressFamilies.ipv4Unicast.networks = [ "10.1.0.0/24" ];
  neighbors."169.254.10.2" = {
    remoteAs = 65002;
    importPolicy.ipv4Unicast.allowCidrs = [ "10.2.0.0/24" ];
    exportPolicy.ipv4Unicast.allowCidrs = [ "10.1.0.0/24" ];
  };
};
```

Learned routes point at the XFRM interface, so they are encrypted. List the
far side's prefixes in `remotePrefixes` too: each gets a blackhole route
with metric 4000, below BGP's routes, so if BGP withdraws a prefix the
traffic is dropped rather than sent in the clear via the WAN default route.

Never route the peer's public address into the tunnel; IKE would follow it
and the tunnel could not come up. Evaluation rejects `routes` or
`remotePrefixes` that cover a literal peer address; for BGP, filter the
peer's address out of what you import.

## No cleartext fallback

Traffic routed into an XFRM interface without a matching SA is dropped by
the kernel, not sent in the clear. The VM test stops strongSwan and checks
that pings to the peer's LAN produce no plaintext on the WAN.

## Flowtables

Keep tunnel interfaces out of `services.router-firewall.flowtable.interfaces`
(evaluation enforces this). Flowtable offload with XFRM interfaces is not
verified here; the default flowtable interfaces (WAN and trusted LANs) do not
include tunnels.

## VRRP failover

The XFRM interfaces are independent of the WAN link, so they exist on both
nodes of a `router-ha` pair. Only the MASTER has its WAN up, so only the
MASTER can negotiate. After a failover:

- The new MASTER's initiator connects from the same public address (with
  `router-ha.wan.clonedMac` and a shared DHCP identity), and the peer
  replaces the old SA.
- DPD on the peer (30 s) clears the stale SA if the new MASTER is not the
  initiator.
- Expect the tunnel to be down for the IKE exchange plus DPD, typically
  seconds to under a minute. BGP over the tunnel reconverges after that.

The old MASTER keeps its strongSwan running. Its attempts fail while its WAN
is down, and the trap re-initiates once it is MASTER again.

## Tested

`vm-router-ipsec` runs two routers on a shared WAN, both with
`router-firewall`:
- The PSK SA comes up (including the retry when the responder starts late).
- Ping through the XFRM interface works.
- BGP is Established over the tunnel, and each LAN is routed via `xfrm-site`.
- A LAN-to-LAN ping works.
- Only ESP appears on the WAN (no ICMP).
- After strongSwan is stopped, no ICMP leaves in the clear.

Eval checks live in `tests/router-ipsec.nix`.
