# Work Item 99: Systemd Slice Isolation & Framework Rebranding

**Status:** ready  
**Priority:** P2 (Medium)  
**Created:** 2026-09-16  

## Description

Introduce systemd resource slices (`router-core.slice` vs. `router-observability.slice` vs. `router-applications.slice`) with memory and CPU boundaries, update `flake.nix` and `README.md` to formally rebrand the framework identity away from "RouterOS-like", and publish the platform compatibility matrix in `docs/COMPATIBILITY.md`.

## Context & Rationale (From Discussion 20)

Telemetry and observability daemons (`ulogd`, `ntopng`, `netdata`, `prometheus`) are prone to upstream nixpkgs drift, memory leaks, or logging storms. Coupling them into the unconstrained host systemd slice risks OOM kills of critical routing services like `kea` or `unbound`. Furthermore, public documentation still emphasizes "RouterOS-like performance", confusing potential adopters about the project's true declarative, topology-driven architecture.

## Objectives

1. Define systemd resource slices in `modules/router-slices.nix`:
   - `router-core.slice`: High priority (`OOMScoreAdjust=-900`, protected memory) for `systemd-networkd`, `nftables`, `kea`, `unbound`, `keepalived`.
   - `router-observability.slice`: Strict limits (`MemoryMax=256M`, `CPUQuota=30%`) for `ulogd`, `netdata`, `ntopng`.
   - `router-applications.slice`: Isolated execution (`MemoryMax=512M`, `CPUQuota=50%`) for Caddy, Tailscale, remote administration.
2. Formally rebrand the framework in `flake.nix` and `README.md`:
   - *"A typed, topology-driven declarative router framework for NixOS: Deterministic edge networking, zone security, and resilient protocol orchestration."*
   - Document the 4-stage pipeline: `typed topology -> derived config -> reproducible deploy -> measurable perf`.
3. Publish `docs/COMPATIBILITY.md` documenting Tier 1 (Proxmox/KVM virtio, Intel NICs), Tier 2 (ARM64 SBCs), and Tier 3 (Realtek) validation states.

## Acceptance Criteria

- [ ] Systemd slices configured with memory and OOM guardrails.
- [ ] Framework documentation and flake description updated to reflect the topology-driven identity.
- [ ] `docs/COMPATIBILITY.md` published and cross-referenced.
