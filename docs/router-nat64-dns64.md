# NAT64 + DNS64

## Overview

NAT64 lets IPv6-only clients reach IPv4-only internet destinations. DNS64 is the
companion that synthesises AAAA records from A records so clients know to use the
NAT64 prefix. Together they enable an IPv6-only LAN without losing access to
IPv4-only servers.

**When you need this:**
- You want IPv6-only LAN segments (no IPv4 assigned to clients)
- You have working IPv6 on the WAN (native or tunnelled)

**When you don't:**
- Dual-stack LAN (clients have both IPv4 and IPv6) — clients reach IPv4 directly

## Prerequisites

| Requirement | Module |
|-------------|--------|
| Working IPv6 WAN (RA or DHCPv6-PD) | `router-networking` |
| Unbound as local DNS resolver | `router-dns-service` with `provider = "unbound"` |
| `router-firewall` loaded (optional but recommended) | `router-firewall` |

DNS64 requires Unbound. It is **not compatible with Technitium** — Technitium has
no built-in DNS64 synthesis. If you use Technitium as your primary resolver, you
would need a separate Unbound instance to act as a forwarding DNS64 resolver for
IPv6-only clients.

## Basic Configuration

```nix
{ inputs, config, ... }:
{
  imports = [
    inputs.nix-router-optimized.nixosModules.router-networking
    inputs.nix-router-optimized.nixosModules.router-firewall
    inputs.nix-router-optimized.nixosModules.router-dns-service
    inputs.nix-router-optimized.nixosModules.router-nat64
    inputs.nix-router-optimized.nixosModules.router-dns64
  ];

  services.router-networking = {
    enable = true;
    wan.device = "ppp0";
    routedInterfaces.lan = {
      device = "enp2s0";
      ipv4Address = "10.10.10.1/24";
      dns = [ "10.10.10.1" ];
    };
  };

  services.router-dns-service = {
    enable = true;
    provider = "unbound";
    listenAddresses = [ "10.10.10.1" "127.0.0.1" ];
  };

  services.router-firewall = {
    enable = true;
    wanInterfaces = [ "ppp0" ];
    lanInterfaces = [ "enp2s0" ];
  };

  # NAT64: Tayga translates IPv6 packets destined for 64:ff9b::/96 into IPv4
  services.router-nat64.enable = true;

  # DNS64: Unbound synthesises AAAA records for A-only names using 64:ff9b::/96
  services.router-dns64.enable = true;
}
```

## Options

### router-nat64

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable NAT64 via Tayga |
| `ipv6Prefix` | `64:ff9b::/96` | IPv6 prefix for NAT64 (Well-Known Prefix) |
| `ipv4Pool` | `192.168.255.0/24` | Internal IPv4 pool for address mapping |
| `ipv4RouterAddr` | `192.168.255.1` | Tayga tunnel interface IPv4 address |
| `ipv6RouterAddr` | `64:ff9b::1` | Tayga tunnel interface IPv6 address |

### router-dns64

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable DNS64 synthesis in Unbound |
| `prefix` | `router-nat64.ipv6Prefix` or `64:ff9b::/96` | NAT64 prefix for AAAA synthesis |

## How It Works

1. A LAN client queries `example.com` and gets only an A record (`93.184.216.34`)
2. Unbound with `dns64` module synthesises `64:ff9b::5db8:d822` (AAAA) from the A record
3. The client sends an IPv6 packet to `64:ff9b::5db8:d822`
4. The kernel routes this to the Tayga `nat64` tunnel (route installed by the NixOS tayga module)
5. Tayga translates the IPv6 packet to IPv4 (`93.184.216.34`) and sends it out
6. The response path is reversed

## Using a Custom Prefix

The Well-Known Prefix `64:ff9b::/96` requires that Tayga's `wkpf-strict` mode
(the default) rejects translation of RFC1918/private IPv4 ranges. If you need to
reach private IPv4 addresses via NAT64 (e.g. in a lab), use a locally-assigned prefix:

```nix
services.router-nat64 = {
  enable = true;
  ipv6Prefix = "fd00:64:ff9b::/96";  # ULA NAT64 prefix
};

services.router-dns64 = {
  enable = true;
  # prefix auto-derives from router-nat64.ipv6Prefix
};
```

You will also need to advertise the custom prefix in your RA configuration if
clients need to know the NAT64 prefix via RFC8781 (PREF64 RA option), which
systemd-networkd does not currently emit automatically.

## Verifying Operation

```bash
# Check Tayga is running
systemctl status tayga

# Check the nat64 tunnel interface
ip addr show nat64
ip -6 route show 64:ff9b::/96

# Test DNS64 synthesis (should return a 64:ff9b:: AAAA)
dig AAAA example.com @127.0.0.1

# Test connectivity through NAT64 (from an IPv6-only client)
ping6 64:ff9b::5db8:d822   # 64:ff9b:: + 93.184.216.34
```

## Firewall Notes

When `router-firewall` is loaded, `router-nat64` automatically adds:
```
iifname "nat64" accept comment "Allow NAT64 translated traffic"
```
to the nftables forward chain. IPv4 egress from Tayga to the WAN is handled by
the standard masquerade rule that `router-firewall` applies to all LAN-origin traffic.
