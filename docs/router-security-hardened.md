# Router Security Hardening

The `router-security-hardened` module provides advanced security features for NixOS routers, focusing on kernel hardening, Geo-IP blocking, WAN egress bogon blocking, and MAC address security.

## Features

### Kernel Hardening
Tightens kernel parameters to reduce attack surface:
- ASLR (Address Space Layout Randomization)
- Restricted `dmesg` access
- Protection against symlink/hardlink attacks
- Strict reverse path filtering (RPF)
- Disabling of dangerous protocols (Source Routing, Redirects)
- Blacklisting of non-essential modules (Firewire, Thunderbolt, etc.)

### Geo-IP Blocking
Declarative blocking of entire countries using `nftables` sets and the IPDeny data source.
- Automatic boot-time and daily updates of IP sets.
- Early drop in the `input` chain before any services are reached.

### WAN Egress Bogon Blocking
Declarative blocking of traffic headed out a WAN interface toward bogon and
special-purpose IPv4 destinations.
- Covers both forwarded LAN-to-WAN traffic and router-originated traffic.
- Scoped to WAN egress only rather than generic local traffic.
- Uses an explicit first-slice IPv4 range set instead of dynamic feeds.

### MAC Security
Interface-specific MAC address whitelisting.
- **Alert mode**: Log unknown MAC addresses and continue normal forward-policy evaluation.
- **Enforce mode**: Log and drop traffic from unknown MAC addresses.
- Early enforcement in the `forward` chain.

## Configuration

```nix
services.router-security-hardened = {
  enable = true;

  kernelHardening = {
    enable = true;
    restrictDmesg = true;
    allowPing = true;
  };

  geoIpBlocking = {
    enable = true;
    blockedCountries = [ "ru" "cn" "ir" ];
  };

  egressBogonBlocking.enable = true;

  macSecurity = {
    enable = true;
    policy = "enforce";
    whitelists = {
      "eth1" = [ "00:11:22:33:44:55" "AA:BB:CC:DD:EE:FF" ];
    };
  };
};
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module. |
| `kernelHardening.enable` | bool | `false` | Enable kernel parameter tuning. |
| `kernelHardening.restrictDmesg` | bool | `true` | Restrict dmesg to root. |
| `kernelHardening.allowPing` | bool | `true` | Allow ICMP echo. |
| `geoIpBlocking.enable` | bool | `false` | Enable Geo-IP blocking. |
| `geoIpBlocking.blockedCountries` | list of str | `[]` | ISO country codes to block. |
| `egressBogonBlocking.enable` | bool | `false` | Enable WAN egress blocking to bogon/special-purpose IPv4 ranges. |
| `egressBogonBlocking.ipv4Cidrs` | list of str | explicit RFC6890-style set | IPv4 CIDRs blocked when traffic exits a WAN interface. |
| `macSecurity.enable` | bool | `false` | Enable MAC address security. |
| `macSecurity.policy` | enum | `"alert"` | `"alert"` or `"enforce"`. |
| `macSecurity.whitelists` | attrs of list of str | `{}` | Per-interface MAC whitelists. |

## Integration Notes

- Requires `services.router-firewall.enable = true` for Geo-IP, WAN egress bogon blocking, and MAC security.
- Geo-IP blocking depends on `https://www.ipdeny.com` for IP zone files.
- WAN egress bogon blocking is IPv4-only in this first slice and is enforced in
  both the `forward` and `output` chains through `router-firewall` extension
  hooks.
- MAC security enforces whitelists on the `forward` chain (traffic passing through the router).
- After enabling or changing this module, use
  [`router-security-validation.md`](./router-security-validation.md) to confirm
  the live router still matches the intended LAN and WAN exposure boundary.
- For risky live changes in this area, use
  [`router-apply-safety.md`](./router-apply-safety.md) before and after the
  switch rather than assuming `nixos-rebuild switch` is its own acceptance gate.
