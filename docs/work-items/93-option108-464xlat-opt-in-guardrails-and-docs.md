# Work Item 93: DHCP Option 108 and 464XLAT Opt-In Guardrails

**Status:** done  
**Assignee:** Agent-Transition-Worker  
**Created:** 2026-08-17  
**Completed:** 2026-08-17  

## Description

Codify and document opt-in options for DHCP Option 108 (RFC 8925) and 464XLAT/CLAT (`router-clat` / RFC 6877) with safety assertions, ensuring they remain opt-in (`enable = false;` by default) for power users while protecting standard dual-stack networks.

## Context & Rationale (From Discussion 19)

DHCP Option 108 (`IPv6-Only Preferred`) instructs dual-stack clients to forgo IPv4 leases. If enabled on a standard dual-stack network without active NAT64/DNS64 (`router-nat64` + `router-dns64`), compliant clients (macOS, Android) will drop IPv4 and fail to reach IPv4-only WAN destinations.

However, offering Option 108 and 464XLAT (`router-clat`) as opt-in features is essential for users deploying experimental IPv6-mostly subnets.

## Objectives

1. Affirm that DHCP Option 108 and `router-clat` remain available as opt-in flake options (`enable = false;` default).
2. Add NixOS module assertions requiring `services.router-nat64.enable = true;` whenever Option 108 or CLAT is enabled.
3. Update `DHCP_SELECTION.md` and `DECLARATIVE_CLAT.md` with explicit safety warnings and deployment prerequisites.

## Acceptance Criteria

- [x] Option 108 and CLAT confirmed as opt-in flake options (`enable = false;` default).
- [x] Safety assertions verified in module code (`Option 108 requires active NAT64/DNS64`, `router-clat requires active NAT64`).
- [x] Documentation updated with clear opt-in prerequisites.
