# Work Item 95: Hardware Optimization Safety Matrix & LRO Removal

**Status:** ready  
**Priority:** P0 (Blocker)  
**Created:** 2026-09-16  

## Description

Purge hazardous `lro on` from `modules/router-optimizations.nix`, enforce safe GRO forwarding defaults, and implement driver-aware hardware offload capability negotiation and runtime status tracking in `/run/router/nic-offload-status.json`.

## Context & Rationale (From Discussion 20)

In `modules/router-optimizations.nix`, the module blindly executes:
```bash
ethtool -K $iface gro on 2>/dev/null || true
ethtool -K $iface lro on 2>/dev/null || true
```
Enabling LRO (Large Receive Offload) on a forwarding router is a critical networking violation. LRO aggregates TCP segments without preserving original transport header checksums or packet boundaries, which silently corrupts forwarded TCP traffic and breaks NAT and connection tracking. Furthermore, offloads like TSO, GSO, and XDP cannot be blindly forced with `|| true` on every NIC/driver (e.g. virtio-net vs realtek vs intel).

## Objectives

1. Immediately purge `lro on` from `modules/router-optimizations.nix`; enforce `lro off` across all routed interfaces.
2. Introduce a 4-state offload status model (`supported`, `enabled`, `effective`, `reason disabled`).
3. Add driver-aware capability negotiation via `ethtool -k` before applying offload modifications, avoiding silent errors or driver stalls.
4. Export `/run/router/nic-offload-status.json` on network activation for observability and diagnostics.
5. Provide profile presets: `intel-baremetal`, `realtek-baremetal`, `virtio-vm`, and `generic`.

## Acceptance Criteria

- [ ] `lro on` completely eliminated from NixOS modules (`modules/`); `ethtool -K <iface> lro off` explicitly verified.
- [ ] Safe GRO and offload negotiation script implemented without blind `|| true` suppressions.
- [ ] Operational state file `/run/router/nic-offload-status.json` generated on activation.
- [ ] Existing eval tests pass without regression.
