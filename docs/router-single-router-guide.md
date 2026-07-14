# Single Router Guide

Start here if you want one router box with one WAN NIC, one LAN NIC, local DNS,
and DHCP.

This is the simplest supported shape in `nix-router-optimized`:

- one active router
- no VRRP or `router-ha`
- one WAN interface managed by `router-networking`
- one LAN interface with a static router IP
- local DNS via `router-dns-service`
- LAN DHCP via `router-dhcp`

If that is your goal, do not start from the HA pair guide.

## What To Import

For a small single-router setup, import only the modules you actually need:

- `router-networking`
- `router-dhcp`
- `router-dns-service`
- `router-firewall`
- `router-optimizations`

That gives you:

- WAN networkd management
- a routed LAN segment
- a small DHCP server for that LAN
- a local resolver
- nftables policy plus interface-role hints

## Copyable Starting Point

Use [`examples/router-single-basic.nix`](../examples/router-single-basic.nix)
as the service-level starting point.

It assumes:

- WAN interface: `wan0`
- LAN interface: `lan0`
- router LAN IP: `192.168.50.1/24`
- local DNS provider: `unbound`

Replace those values with your real interfaces and subnet before deployment.

Example flake usage:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    router-optimized.url = "github:deepwatrcreatur/nix-router-optimized";
  };

  outputs = { self, nixpkgs, router-optimized, ... }: {
    nixosConfigurations.router = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        router-optimized.nixosModules.router-networking
        router-optimized.nixosModules.router-dhcp
        router-optimized.nixosModules.router-dns-service
        router-optimized.nixosModules.router-firewall
        router-optimized.nixosModules.router-optimizations
        ./router-single-basic.nix
        {
          networking.hostName = "router";
          system.stateVersion = "25.11";
        }
      ];
    };
  };
}
```

Before using that snippet, copy
[`examples/router-single-basic.nix`](../examples/router-single-basic.nix) into
your own flake as `./router-single-basic.nix`, then edit the interface names
and subnet for your environment.

## What Not To Enable Yet

Do not add `services.router-ha` unless you are actually building and testing a
two-node failover design.

For a first bring-up, also avoid stacking many optional router services at the
same time. Get these working first:

- WAN gets a route
- LAN clients get DHCP leases
- LAN clients can resolve names
- LAN clients can reach the Internet

Then add extras such as tunnels, remote access, BGP, or network sensors as
separate slices.

## First Boot Checklist

After first boot, verify:

- the WAN interface has carrier and a default route
- the LAN interface owns the router IP you configured
- DHCP is actually listening on the LAN IP
- DNS is actually listening on `127.0.0.1` and the LAN IP
- a fresh LAN client can obtain a lease and resolve names

Useful checks:

```bash
ip -o -4 addr show dev lan0
ip route show default
sudo ss -tulpn | grep -E '(:53 |:67 )'
getent ahostsv4 github.com
ping -c 2 1.1.1.1
```

## When To Choose A Different Path

Use a different guide if:

- you want two routers with VRRP or shared ownership:
  see [`router-ha-pair-guide.md`](./router-ha-pair-guide.md)
- you need multi-WAN policy/failover:
  see [`router-mwan.md`](./router-mwan.md)
- you are choosing an IPv6 translation strategy:
  see [`router-ipv6-approach-guide.md`](./router-ipv6-approach-guide.md)
