# Router Security Hardening

The `router-security-hardened` module provides advanced security features for NixOS routers, focusing on kernel hardening, Geo-IP blocking, and MAC address security.

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
| `macSecurity.enable` | bool | `false` | Enable MAC address security. |
| `macSecurity.policy` | enum | `"alert"` | `"alert"` or `"enforce"`. |
| `macSecurity.whitelists` | attrs of list of str | `{}` | Per-interface MAC whitelists. |

## Integration Notes

- Requires `services.router-firewall.enable = true` for Geo-IP and MAC security.
- Geo-IP blocking depends on `https://www.ipdeny.com` for IP zone files.
- MAC security enforces whitelists on the `forward` chain (traffic passing through the router).
- For risky live changes in this area, use
  [`router-apply-safety.md`](./router-apply-safety.md) before and after the
  switch rather than assuming `nixos-rebuild switch` is its own acceptance gate.
