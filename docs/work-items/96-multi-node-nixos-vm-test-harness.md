# Work Item 96: Multi-Node NixOS VM Test Harness

**Status:** ready  
**Priority:** P0 (Blocker)  
**Created:** 2026-09-16  

## Description

Implement multi-node QEMU virtual integration tests (`nixosTests`) in `tests/vm/` using `pkgs.testers.runNixOSTest`, validating DHCP lease assignment, NAT masquerade forwarding, local DNS resolution, and zone drop policies across virtual nodes before bare-metal deployment.

## Context & Rationale (From Discussion 20)

Currently, all 22 tests in `nix-router-optimized` are pure evaluation tests (`mkNixosEvalCheck`). The repository lacks runtime verification that booted kernels load nftables rulesets without syntax errors, that `systemd-networkd` properly binds interfaces, that Kea DHCP actually leases IPs over the wire, and that inter-zone traffic is strictly isolated.

## Objectives

1. Create a reusable virtual test builder in `tests/vm/lib/mk-router-test.nix`.
2. Build `tests/vm/router-basic-smoke.nix` featuring a 3-node topology:
   - `wanSimulator`: Upstream ISP node serving DHCPv4/v6 and upstream DNS.
   - `router`: The `nix-router-optimized` node with WAN, LAN, and IoT interfaces.
   - `client`: Downstream client acquiring DHCP leases and verifying internet egress.
3. Test invariants:
   - Client acquires LAN IPv4 and default gateway via DHCP from router.
   - Client pings `wanSimulator` through router with verified NAT masquerade.
   - Client resolves local router hostnames and forward DNS.
   - Negative firewall test: IoT client attempts to access LAN subnet and is rejected.
4. Expose the test under `checks.<system>.vm-smoke` in `flake.nix`.

## Acceptance Criteria

- [ ] `tests/vm/router-basic-smoke.nix` successfully runs and passes in headless QEMU.
- [ ] Invariants for DHCP, NAT, DNS, and Zone isolation are asserted via python `testScript`.
- [ ] `nix flake check` or `nix build .#checks.x86_64-linux.vm-smoke` evaluates and executes cleanly.
