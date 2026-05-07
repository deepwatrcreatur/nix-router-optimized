# IPv6 Provisioning Domains (PvDs)

## Overview
Vaglio supports RFC 8028 Provisioning Domains (PvDs), which allow a router to advertise multiple IPv6 prefixes on the same LAN while associating each with specific metadata such as DNS servers, HTTP proxies, and captive portal URIs.

This is especially useful for routers connected to multiple uplinks (e.g., a standard ISP WAN and a VPN like Tailscale or WireGuard), as it allows clients to make informed decisions about which prefix to use for which destination, avoiding the need for NAT66 or NPTv6.

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
Vaglio implements PvD support using `systemd-networkd`'s `[IPv6SendRA]` and `[IPv6PvD]` sections. When `pvds` are defined for an interface, Vaglio:
1. Enables `PvD=yes` in the `[IPv6SendRA]` section.
2. Appends one or more `[IPv6PvD]` sections to the network configuration with the specified `Identifier`, `HFlag`, and `SequenceNumber`.
