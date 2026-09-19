# Work Item 101: Upstream UDP GRO Forwarding Offload Configuration

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-19  

## Description

Add `rx-udp-gro-forwarding on rx-gro-list off` configuration to interface hardware offload initialization in `modules/router-optimizations.nix`.

## Context & Rationale

When Generic Receive Offload (GRO) is enabled on a router forwarding UDP traffic (such as WireGuard VPN tunnels, Tailscale exit nodes, QUIC streams, and high-volume DNS), Linux kernel GRO list can cause packet reordering, latency jitter, or silent drops unless UDP GRO forwarding is explicitly turned on and GRO list is disabled.

Currently, `configure_interface` in `modules/router-optimizations.nix` executes:
```bash
${pkgs.ethtool}/bin/ethtool -K $iface tso on 2>/dev/null || true
${pkgs.ethtool}/bin/ethtool -K $iface gso on 2>/dev/null || true
${pkgs.ethtool}/bin/ethtool -K $iface gro on 2>/dev/null || true
```
Downstream production routers had to work around this by appending an out-of-band `systemd.services.router-hardware-offload.postStart` hook. This should be built directly into the upstream module.

## Objectives

1. Update `configure_interface` in `modules/router-optimizations.nix` to configure:
   ```bash
   ${pkgs.ethtool}/bin/ethtool -K $iface rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null || true
   ```
2. Integrate this with Work Item 95's driver capability negotiation matrix.

## Acceptance Criteria

- [ ] All configured interfaces receive `rx-udp-gro-forwarding on rx-gro-list off` during `router-hardware-offload.service` execution.
- [ ] Evaluation tests verify `systemd.services.router-hardware-offload` script contents.
