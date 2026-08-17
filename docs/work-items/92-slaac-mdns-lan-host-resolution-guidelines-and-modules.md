# Work Item 92: SLAAC + mDNS LAN Host Resolution Guidelines

**Status:** done  
**Assignee:** Agent-DNS-Worker  
**Created:** 2026-08-17  
**Completed:** 2026-08-17  

## Description

Standardize LAN hostname discovery guidelines around SLAAC + mDNS (`systemd-resolved` / Avahi), explicitly documenting why stateful DHCPv6 DDNS registration is disabled by default in `nix-router-optimized`.

## Context & Rationale (From Discussion 19)

Stateful DHCPv6 for LAN host DNS registration is fundamentally broken on modern mobile and IoT client operating systems:
- Android explicitly refuses to support stateful DHCPv6 (M-flag).
- iOS and macOS prioritize SLAAC with Privacy Extensions (RFC 8981).

Relying on stateful DHCPv6 as the primary DNS registration mechanism leaves mobile and IoT devices without IPv6 or unregistered in local DNS. The recommended path is **SLAAC** for IP assignment combined with **mDNS** (`systemd-resolved` / Avahi) or client RFC 2136 updates for `.local` / LAN hostname discovery.

## Objectives

1. Add explicit maintainer guidance in `DHCP_SELECTION.md` and `router-ipv6-approach-guide.md` discouraging stateful DHCPv6 for host DNS registration.
2. Document the recommended SLAAC + mDNS configuration pattern for `nix-router-optimized` LAN interfaces.
3. Provide example `systemd-resolved` and Avahi configuration stanzas for zero-config LAN host resolution across Linux, macOS, and iOS clients.

## Acceptance Criteria

- [x] Clear warning against stateful DHCPv6 host registration added to `DHCP_SELECTION.md`.
- [x] Recommended SLAAC + mDNS setup documented in `router-ipv6-approach-guide.md`.
- [x] Example stanzas for `systemd-resolved` mDNS enablement verified.

