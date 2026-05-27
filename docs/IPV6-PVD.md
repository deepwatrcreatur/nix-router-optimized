# IPv6 Provisioning Domains (PvDs)

## Overview
`nix-router-optimized` supports Provisioning Domains (PvDs) for native
multi-prefix IPv6 signaling. PvDs let a router advertise multiple IPv6 prefixes
on the same LAN while associating each with specific metadata such as DNS
servers, HTTP proxies, and captive portal URIs.

This is especially useful for routers connected to multiple uplinks, because it
allows clients to make informed decisions about which prefix to use for which
destination without immediately reaching for translation.

For the broader operator decision ladder, read
[`ipv6-multiwan-guide.md`](./ipv6-multiwan-guide.md). In that guide, PvD /
native multi-prefix is the **preferred** answer when client support is good
enough.

## Configuration
PvDs are configured in the `services.router-networking.routedInterfaces` attribute set.

Example:
```nix
services.router-networking.routedInterfaces.lan0 = {
  device = "lan0";
  ipv4Address = "10.10.10.1/24";
  pvds = [
    {
      identifier = "isp.example.com";
      hFlag = false;
    }
    {
      identifier = "vpn.example.com";
      hFlag = true;
      sequenceNumber = 42;
    }
  ];
};
```

## Client Support
PvDs (RFC 8801) are a modern standard and require client-side support to be effective.

| Client OS | Support Version | Notes |
| :--- | :--- | :--- |
| **Android** | Android 10+ | Supports multiple prefixes and PVD-specific DNS. |
| **iOS / macOS** | iOS 14+, macOS 11+ | Supports RFC 8801 and "Additional Information" via HTTPS (H-Flag). |
| **Linux** | systemd-networkd v254+ | Supports both sending and receiving PvDs. |
| **Windows** | Windows 10/11 | Partial support; verify with recent updates. |

## Implementation Details
`nix-router-optimized` implements PvD support using `systemd-networkd`'s
`[IPv6SendRA]` and `[IPv6PvD]` sections. When `pvds` are defined for an
interface, the repo:
1. Enables `PvD=yes` in the `[IPv6SendRA]` section.
2. Appends one or more `[IPv6PvD]` sections to the network configuration with the specified `Identifier`, `HFlag`, and `SequenceNumber`.
