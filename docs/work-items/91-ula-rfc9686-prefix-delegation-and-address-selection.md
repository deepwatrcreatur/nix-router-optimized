# Work Item 91: ULA (RFC 9686) Prefix Delegation and Address Selection

**Status:** done  
**Assignee:** Agent-ULA-Worker  
**Created:** 2026-08-17  
**Completed:** 2026-08-17  

## Description

Incorporate ULA (Unique Local Address, `fd00::/8`) configuration options and RFC 9686 / RFC 6724bis address selection guidance into `nix-router-optimized`.

## Context & Rationale (From Discussion 19)

Consumer ISPs often assign dynamic IPv6 Global Unicast Address (GUA) prefixes via DHCPv6-PD that rotate on router reboot or reconnection. If internal homelab services (`homeserver`, `attic-cache`, `proxmox`) rely strictly on GUA, internal DNS records and inter-host connections break whenever the ISP rotates the prefix.

Assigning a ULA prefix (`fd00::/8`) alongside GUA via Router Advertisements guarantees permanent, non-changing internal IPv6 addresses. Under RFC 9686 and RFC 6724bis, modern operating systems properly prioritize ULA for internal LAN traffic while using GUA for internet egress.

## Objectives

1. Document declarative ULA prefix delegation options in `nix-router-optimized` LAN modules (`router-networking` / RADVD / `systemd-networkd`).
2. Provide clear examples showing how to configure ULA (`fd00:xxxx:xxxx::/48`) alongside ISP-delegated GUA.
3. Link to `docs/discussions/19-dhcpv6-ula-rfc9686-and-option108-464xlat-strategy.md` in `router-ipv6-approach-guide.md`.

## Acceptance Criteria

- [x] Declarative ULA prefix option documented in LAN router interface guides.
- [x] Sample NixOS stanzas added for dual-prefix (GUA + ULA) Router Advertisements.
- [x] Inter-host stability guidance validated against `unified-nix-configuration` architecture.
