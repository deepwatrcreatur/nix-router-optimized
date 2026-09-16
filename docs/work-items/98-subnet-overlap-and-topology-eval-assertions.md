# Work Item 98: Subnet Overlap, MTU & Topology Invariant Assertions

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-16  

## Description

Implement pure Nix evaluation-time assertions in `modules/lib/ip.nix` and `modules/router-networking.nix` that detect invalid router configurations (overlapping routed prefixes, DHCP pool misallocations, MTU violations, VRRP VIP collisions) during `nixos-rebuild` or `nix flake check`.

## Context & Rationale (From Discussion 20)

Nix evaluation is exceptionally capable of catching misconfigurations before system activation. Currently, `router-zones` only verifies string interface uniqueness, allowing catastrophic typos (such as overlapping LAN and WAN CIDRs, or DHCP pools defined outside an interface's subnet) to evaluate successfully and fail only at runtime when `systemd-networkd` refuses to bind addresses.

## Objectives

1. Implement a pure Nix IP CIDR calculation library (`modules/lib/ip.nix`) supporting IPv4 and IPv6 subnet parsing, containment, and overlap detection.
2. Add the following evaluation-time assertions:
   - **Subnet Overlap:** Pairwise non-overlap across all routed interface prefixes (`services.router-networking.routedInterfaces`).
   - **DHCP Pool Containment:** All Kea and systemd-networkd DHCP ranges must be strictly contained within the parent interface's subnet.
   - **VLAN MTU Invariant:** Child VLAN MTUs must never exceed parent device MTUs.
   - **VRRP VIP Separation:** Virtual IPs in `services.router-ha` must not collide with static interface IP addresses on the same subnet.
3. Add a negative evaluation test suite verifying that invalid configurations fail with clean, human-readable error messages.

## Acceptance Criteria

- [ ] Pure Nix IP CIDR utility tests pass.
- [ ] Overlapping routed subnets trigger build-time assertion failure.
- [ ] Out-of-bounds DHCP pools trigger build-time assertion failure.
- [ ] Negative test suite verifies assertion messages.
