# Router BGP

`services.router-bgp` is a thin wrapper around FRR `bgpd` for advanced users who
want simple, declarative internal BGP peering without writing the full FRR
configuration by hand.

Current support stance:

- advanced / experimental opt-in
- intended for controlled lab and small-infrastructure deployments
- not yet validated as HA-ready in combination with `router-ha`
- not yet feature-complete for production-facing peering

## What The Wrapper Currently Does

When enabled, the module:

- enables `services.frr.bgpd`
- renders a small BGP config from:
  - local ASN
  - optional router ID
  - neighbor IPs and remote ASNs
  - optional neighbor descriptions
  - optional per-neighbor `next-hop-self`
  - a list of advertised `network` prefixes
- opens TCP `179` through:
  - `services.router-firewall.trustedTcpPorts` when `router-firewall` is
    imported and enabled
  - `networking.firewall.allowedTCPPorts` otherwise

The current module now provides a first serious production-oriented slice:

- per-neighbor runtime `passwordFile` support
- explicit `ipv4-unicast` and `ipv6-unicast` address-family controls
- bounded import/export policy controls for common small-scale routing cases

The module still does **not** yet provide:

- raw FRR policy-language passthrough as a first-class wrapper surface
- broader AFI / SAFI support beyond IPv4/IPv6 unicast
- promotion-aware ownership behavior with `router-ha`

## Intended User

Good current fit:

- Proxmox or hypervisor route exchange in a lab
- small internal BGP topologies
- advanced homelab users who already understand FRR and BGP operations
- cluster or routed-overlay experimentation where a thin wrapper is enough

Poor current fit:

- default home-router deployments
- users expecting turnkey production peering defaults
- users needing hardened external peering features
- users expecting polished HA promotion behavior

## Minimal Example

```nix
{
  imports = [
    router-optimized.nixosModules.router-bgp
  ];

  services.router-bgp = {
    enable = true;
    asn = 65001;
    routerId = "10.10.10.1";
    neighbors."10.10.10.2" = {
      remoteAs = 65002;
      description = "upstream-lab-router";
      nextHopSelf = true;
    };
    networks = [
      "10.10.20.0/24"
      "10.10.30.0/24"
    ];
  };
}
```

## Authenticated Dual-Stack Example

```nix
{
  imports = [
    router-optimized.nixosModules.router-bgp
  ];

  services.router-bgp = {
    enable = true;
    asn = 65001;
    routerId = "10.10.20.1";

    addressFamilies = {
      ipv4Unicast = {
        enable = true;
        networks = [ "10.10.20.0/24" ];
      };
      ipv6Unicast = {
        enable = true;
        networks = [ "fd00:20::/64" ];
      };
    };

    neighbors."10.10.254.2" = {
      remoteAs = 65010;
      passwordFile = "/run/agenix/bgp-proxmox-password";
      addressFamilies = [
        "ipv4-unicast"
        "ipv6-unicast"
      ];

      importPolicy.ipv4Unicast = {
        allowCidrs = [ "10.10.0.0/16" ];
        defaultAction = "deny";
      };

      exportPolicy.ipv6Unicast = {
        allowCidrs = [ "fd00:20::/64" ];
        denyCidrs = [ "::/0" ];
        defaultAction = "deny";
      };
    };
  };
}
```

## Realistic Lab Example

See [examples/router-bgp-proxmox-lab.nix](../examples/router-bgp-proxmox-lab.nix)
for a fuller example showing:

- `router-networking`
- `router-firewall`
- explicit WAN/LAN firewall interface declarations
- a routed LAN subnet
- a dedicated lab transit link
- the transit link marked as a trusted router-facing interface
- an internal BGP peer such as a Proxmox or FRR node

## Options Summary

| Option | Purpose |
|---|---|
| `services.router-bgp.enable` | Enable the wrapper and FRR `bgpd`. |
| `services.router-bgp.asn` | Local autonomous system number. |
| `services.router-bgp.routerId` | Optional router ID, ideally a stable unique per-node IPv4-style identifier. |
| `services.router-bgp.neighbors` | Per-neighbor map of remote ASN, description, runtime auth file, AFI activation, and bounded policies. |
| `services.router-bgp.networks` | Legacy IPv4 prefixes to advertise when `addressFamilies.ipv4Unicast.networks` is empty. |
| `services.router-bgp.addressFamilies.ipv4Unicast` | Explicit IPv4 unicast enablement and advertised networks. |
| `services.router-bgp.addressFamilies.ipv6Unicast` | Explicit IPv6 unicast enablement and advertised networks. |

## Router ID Guidance

Treat the BGP router ID as **stable node identity**, not as shared service
identity.

- For small flake consumers, the best default recommendation is a simple,
  explicit, per-node IPv4-style value such as `10.255.0.1` or `10.255.0.2`.
- In IPv6-native deployments, the router ID is still a 32-bit BGP identifier, so
  using a dedicated private IPv4-style value is fine.
- In HA pairs, each node should keep its **own** fixed router ID.
- Do **not** derive the router ID from a shared VIP.
- Do **not** rely on a dynamic LAN address if you want stable peering identity.

This repo does **not** currently impose a provider-style structured numbering
scheme for router IDs. If a consumer wants function / region / instance
encoding, they can choose it themselves, but the flake should not require it as
the default convention.

## Configuration Model

The wrapper now uses three layers:

1. **Base router identity**
   - local ASN
   - optional router ID
   - explicit per-node router ID strongly recommended for HA-capable or
     IPv6-native deployments

2. **Per-neighbor transport and activation**
   - remote ASN
   - optional runtime `passwordFile`
   - which address families the peer should activate
   - optional `nextHopSelf`

3. **Bounded route policy**
   - per-neighbor import/export policy
   - per address family
   - allow list
   - deny list
   - default action

This is intentionally narrower than full FRR policy language. It is meant to
cover common small-scale routing needs without forcing users to hand-write
raw route-map syntax everywhere.

## Operational Verification

After deployment, verify the session operationally rather than assuming config
generation means peering is healthy.

Recommended checks:

1. Confirm FRR is running:

```bash
systemctl status frr
systemctl status frr-bgpd || systemctl status bgpd
```

2. Confirm the listener exists:

```bash
ss -ltn sport = :179
```

3. Inspect the rendered BGP state:

```bash
vtysh -c 'show running-config'
vtysh -c 'show bgp summary'
```

4. For a specific peer, inspect neighbor state:

```bash
vtysh -c 'show bgp neighbor 10.10.10.2'
```

5. Confirm advertised and learned routes match expectations:

```bash
vtysh -c 'show bgp ipv4 unicast'
ip route
```

6. If peering is not establishing, check the basics:

- local and remote ASN values
- neighbor IP reachability
- TCP `179` filtering on both sides
- stable per-node router ID selection
- whether the remote peer expects authentication or policy not yet modeled here

## HA Boundary

BGP with HA is supported through a **single-active-owner** model:

```nix
services.router-bgp = {
  enable = true;
  asn = 65001;
  routerId = "10.10.10.1";
  ha.singleActiveOwner = true;
  neighbors."10.10.254.2" = { remoteAs = 65010; };
};

services.router-ha = {
  enable = true;
  role = "master";
  virtualIp = "10.10.10.1/24";
  vrrpInterface = "lan0";
};
```

### How it works

1. FRR `bgpd` starts on both nodes with all neighbors in `shutdown` state
2. When a node becomes VRRP **MASTER**, keepalived runs `vtysh` to activate
   each neighbor (`no neighbor <ip> shutdown`)
3. When a node becomes **BACKUP** or **FAULT**, keepalived shuts down all
   neighbors again

This ensures only one node presents active BGP peering identity at any time.

### Constraints

- `ha.singleActiveOwner` requires `services.router-ha.enable = true`
- Without `singleActiveOwner`, BGP + HA is still blocked by assertion
- The promotion/demotion window is bounded by vtysh execution time, not
  by a full FRR restart
- Both nodes must have identical FRR config (same ASN, neighbors, policies)
- Each node must keep its own fixed `routerId`; do not reuse the shared
  `virtualIp` as the BGP router ID
- Split-brain is possible if VRRP itself partitions — this is a VRRP
  limitation, not a BGP ownership limitation

## Roadmap Boundary

The next maturity steps are already separated in the queue:

- firewall and validation cleanup
- explicit HA boundary / guardrails
- neighbor authentication, AFI / SAFI, and bounded policy controls

So the current doc should be read as:

- "BGP is intentionally available"
- not "BGP is already a polished production router feature"
