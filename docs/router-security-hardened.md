# Router Security Hardening

The `router-security-hardened` module provides advanced security features for NixOS routers, focusing on kernel hardening, Geo-IP blocking, WAN egress bogon blocking, and MAC address security.

## Features

### Kernel Hardening
Tightens kernel parameters to reduce attack surface:
- ASLR (Address Space Layout Randomization)
- Restricted `dmesg` access
- Protection against symlink/hardlink attacks
- Reverse path filtering (RPF): strict by default, `loose` or `off` via
  `kernelHardening.rpFilter`
- Disabling of dangerous protocols (Source Routing, Redirects)
- BPF JIT hardening and no core dumps from setuid processes
- Blocking of non-essential modules (legacy protocols such as TIPC, RDS and
  AX.25; FireWire, Thunderbolt, Bluetooth, webcams). By default they are
  refused even when loaded by name or as a dependency, not only blacklisted.

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
    rpFilter = "strict"; # "loose" on VRRP members and multi-WAN routers
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
| `kernelHardening.rpFilter` | enum | `"strict"` | `rp_filter` for `all` and `default`: `"strict"` (1), `"loose"` (2) or `"off"` (0). |
| `kernelHardening.blacklistedModules` | list of str | legacy protocols and desktop peripherals | Modules never loaded. Replace the list to keep one the hardware needs. |
| `kernelHardening.denyExplicitLoad` | bool | `true` | Also refuse `blacklistedModules` by name or as a dependency (`install <module> false`). |
| `geoIpBlocking.enable` | bool | `false` | Enable Geo-IP blocking. |
| `geoIpBlocking.blockedCountries` | list of str | `[]` | ISO country codes to block. |
| `egressBogonBlocking.enable` | bool | `false` | Enable WAN egress blocking to bogon/special-purpose IPv4 ranges. |
| `egressBogonBlocking.ipv4Cidrs` | list of str | explicit RFC6890-style set | IPv4 CIDRs blocked when traffic exits a WAN interface. |
| `macSecurity.enable` | bool | `false` | Enable MAC address security. |
| `macSecurity.policy` | enum | `"alert"` | `"alert"` or `"enforce"`. |
| `macSecurity.whitelists` | attrs of list of str | `{}` | Per-interface MAC whitelists. |

## Integration Notes

- **Reverse-path filtering and HA.** Strict `rp_filter` drops legitimate
  traffic that arrives on a different interface from the one its source
  routes back through: a VRRP backup whose default route points at the
  master, multi-WAN with policy routing, asymmetric transit. Set
  `kernelHardening.rpFilter = "loose"` there. The kernel uses the higher of
  the `all` and per-interface values, so `router-multicast`'s per-interface
  loose setting keeps working under `strict`.
- **Changing `rpFilter` on a running router.** Once an interface has an
  address, Linux no longer copies `default` into it, and filtering uses the
  higher of `all` and the interface value. The `router-rp-filter-reset` unit
  therefore sets every existing interface's own value to 0 at boot and
  whenever `rpFilter` changes, so `all` decides without a reboot. It skips
  `router-multicast`'s upstream when that module sets it to loose.
- **Blocked modules.** Since `denyExplicitLoad` (on by default),
  `modprobe <module>` fails for every entry in `blacklistedModules`, and so
  do modules that depend on one (for example `thunderbolt-net`). Remove the
  entry or set `denyExplicitLoad = false` if a router needs it.

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
