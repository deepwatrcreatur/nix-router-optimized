# Work Item 94: Routed Interface IPv6 RA Control and Gateway Lifetime

**Status:** active  
**Assignee:** Antigravity  
**Created:** 2026-09-15  

## Description

Add declarative configuration options for IPv6 Router Advertisements (`ipv6SendRA`), DHCPv6 Prefix Delegation (`dhcpPrefixDelegation`), and router default gateway lifetime (`routerLifetimeSec`) to `services.router-networking.routedInterfaces`.

## Context & Rationale

Currently, `modules/router-networking.nix` hardcodes `IPv6SendRA = true;` and `DHCPPrefixDelegation = true;` for every configured routed interface.

In multi-node, HA, or standby router topologies (such as `router` and `router-backup` in `unified-nix-configuration`), standby or management interfaces configured as routed segments unconditionally emit Router Advertisements claiming default router status. When downstream clients receive RAs from both the active router and an inactive/standby node (which has no active WAN uplink), client kernels install equal-cost multipath (ECMP) default routes. IPv6 traffic hashing to the standby node is blackholed, causing intermittent ~50% packet loss to various destinations.

Exposing declarative toggles allows:
1. Standby router nodes without WAN uplinks to disable RA broadcasting entirely (`ipv6SendRA = false`).
2. Internal/management segments to prevent unwanted RA pollution and prefix delegation leakage.
3. Specific interfaces to advertise local prefixes without advertising internet default gateway reachability (`routerLifetimeSec = 0`).

## Objectives

1. Add `ipv6SendRA` (boolean, default `true`), `dhcpPrefixDelegation` (boolean, default `true`), and `routerLifetimeSec` (nullable int, default `null`) options to `routedInterfaceModule` in `modules/router-networking.nix`.
2. Wire `networkConfig.IPv6SendRA = iface.ipv6SendRA;` and `networkConfig.DHCPPrefixDelegation = iface.dhcpPrefixDelegation;`.
3. Support setting `[IPv6SendRA] RouterLifetimeSec` when `iface.routerLifetimeSec` is specified.
4. Add NixOS eval checks validating that disabling RA emission and configuring router lifetime renders correctly in `systemd.network.networks`.

## Acceptance Criteria

- [x] `services.router-networking.routedInterfaces.<name>.ipv6SendRA` allows disabling RA emission (`IPv6SendRA = false`).
- [x] `services.router-networking.routedInterfaces.<name>.dhcpPrefixDelegation` allows disabling PD on select routed interfaces.
- [x] `services.router-networking.routedInterfaces.<name>.routerLifetimeSec` sets `RouterLifetimeSec` under `[IPv6SendRA]`.
- [x] NixOS eval test verifies correct `systemd-networkd` configuration generation.
