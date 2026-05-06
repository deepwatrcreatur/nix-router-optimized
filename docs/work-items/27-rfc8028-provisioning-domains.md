# 27 — RFC 8028 Provisioning Domains (PvDs) Support

## Status: `in-progress` — **Gemini**

## Objective
Implement support for RFC 8028 Provisioning Domains to allow NAT-less IPv6 redirection for modern, PvD-aware clients.

## Rationale
While NPTv6 (Item 24) and NAT66 (Item 25) provide pragmatic solutions for travel routers and hostile upstreams, "Pure" IPv6 redirection should rely on the client making informed decisions about which prefix to use for which destination. PvDs allow the router to advertise multiple prefixes while associating each with specific DNS and gateway metadata.

## Requirements
- [ ] Implement an abstraction for defining multiple Provisioning Domains in `services.router-networking`.
- [ ] Configure `radvd` or `systemd-networkd` to emit RA options for PvDs (RFC 8801).
- [ ] Integrate with the VPN modules to associate a specific VPN prefix/DNS with a named PvD.
- [ ] Provide documentation on which clients (Android 10+, iOS 14+, Linux systemd-resolved) currently support this mechanism.

## Verification
- [ ] Lab test: Verify that a PvD-aware client receives multiple prefixes and correctly selects the VPN-associated prefix when querying a destination associated with the VPN's DNS.
