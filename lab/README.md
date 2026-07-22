# Router HA Lab

This directory contains the **interactive** HA development lab for
`nix-router-optimized`.

The current phase-1 backend is:

- `systemd-nspawn`

This lab is intentionally separate from the repo's cheap eval-oriented checks in
[`tests/`](../tests/README.md). The intended split is:

- `lab/` for fast local iteration, manual rehearsal, and topology debugging
- `tests/` for later deterministic VM/regression coverage once the scenarios
  stabilize

## Current Scope

The first topology is:

- `router`
- `router-backup`
- `wan`
- `client`

with:

- one flat `lan-net`
- one flat `wan-net`
- one VIP on the LAN side
- one bounded single-active demo unit
- no automatic DHCP failover claim

This is a **control-plane harness**, not a final proof of production-grade HA.

## Safety Rules

The lab must not interfere with the real homelab.

Required boundaries:

- no physical NIC attachment
- lab-only bridge and machine names
- no forwarding path from the lab into the real LAN or WAN
- documentation/test address space only
- explicit create/destroy tooling

The scripts under `lab/nspawn/scripts/` are written with those boundaries in
mind.

## Start Here

- [`nspawn/README.md`](./nspawn/README.md)
- [`../docs/router-ha-lab-plan.md`](../docs/router-ha-lab-plan.md)

## Current Runtime Boundary

The phase-1 lab is now documented at two levels:

- the planning boundary in [`../docs/router-ha-lab-plan.md`](../docs/router-ha-lab-plan.md)
- the backend-specific runtime status in [`nspawn/README.md`](./nspawn/README.md)

The important current distinction is:

- the topology and script entry points are checked into `main`
- the live `nspawn` rehearsal now passes the bounded phase-1 runtime assertions
- the runtime backend still has explicit host-side caveats that should remain
  documented, especially bridge-netfilter handling and manual veth plumbing

So this subtree should be read as a real working HA lab harness with a bounded
scope, not as a finished production-like simulator.
