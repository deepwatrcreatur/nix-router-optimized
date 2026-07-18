# 91 - Router HA Lab `systemd-nspawn` Phase-1 Harness

## Status: `ready`

## Objective

Add the **first safe isolated HA development harness** for
`nix-router-optimized` using a small `systemd-nspawn` / NixOS-container lab.

The goal is not to prove production-grade HA. The goal is to create a fast
inner loop that can safely exercise:

- keepalived / VRRP election
- VIP ownership
- bounded single-active service behavior
- promotion / demotion drills

without touching the real homelab network.

Suggested branch: `feat/router-ha-lab-nspawn-harness`

## Rationale

Discussion 18 concluded that recent live HA work created too much operational
risk and that the repo needs an isolated lab before revisiting more serious HA
development.

The recommended first backend is `systemd-nspawn` because it gives:

- fast local iteration
- direct reuse of NixOS module surfaces
- real `systemd`, `systemd-networkd`, keepalived, and nftables behavior

while staying clearly bounded away from:

- physical NIC realism
- real ISP/WAN behavior
- production-grade failover claims

The resulting lab should act as:

- a design sandbox
- a safe scenario-rehearsal surface
- and a feeder path for later NixOS VM tests

not as a replacement for all later validation.

## Requirements

- [ ] Add a new `lab/` subtree for interactive HA lab work
- [ ] Add a top-level `lab/README.md`
- [ ] Add an initial `nspawn`-specific layout under `lab/nspawn/`
- [ ] Add one first topology, scoped roughly as:
      - `router`
      - `router-backup`
      - `wan` or `upstream-sim`
      - `client`
- [ ] Keep the topology flat and lab-only:
      - one `lan-net`
      - one `wan-net`
      - no physical NIC attachment
- [ ] Add create/run/destroy scripts or equivalent entrypoints for the lab
- [ ] Enforce host-local safety boundaries so the lab cannot accidentally route
      into the real homelab
- [ ] Add at least one scenario/assertion path that proves:
      - one node wins VIP ownership
      - the VIP is not dual-owned
- [ ] Add at least one bounded single-active service-ownership drill
- [ ] Keep DHCP in the current support posture:
      - no automatic DHCP failover claim
      - manual/single-active behavior only
- [ ] Document what the lab is good enough for
- [ ] Document what the lab is not good enough for

## Verification

- [ ] A contributor can stand up the lab without changing the host's production
      router configuration
- [ ] The lab uses only lab-local bridges/veths/namespaces and test address
      space
- [ ] The first scenario shows exactly one VRRP owner for the VIP
- [ ] The scenario surface is small enough to iterate quickly instead of trying
      to simulate the whole homelab
- [ ] The docs explicitly say the lab is a phase-1 control-plane harness, not a
      final proof of router-grade HA

## Non-Goals

This item does **not** require:

- real ISP interaction
- PPPoE realism
- multi-WAN
- BGP failover
- automatic Kea HA revival
- full IPv6 PD realism
- throughput/performance benchmarking
- CI integration for the raw `nspawn` harness

Those can be revisited later, after the first safe isolated harness exists.

## Follow-On Direction

If this harness works well, later work should:

- tighten the scenarios
- encode the most stable ones as NixOS VM tests
- and only then consider broader HA surfaces

The intended progression is:

1. `nspawn` for fast safe learning
2. VM tests for durable regression coverage
3. broader HA work after the first two layers are trustworthy
