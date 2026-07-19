# `systemd-nspawn` HA Lab

This subtree holds the first interactive HA lab backend for
`nix-router-optimized`.

## Topology

Current phase-1 topology:

- `ha-basic`

Nodes:

- `router`
- `router-backup`
- `wan`
- `client`

Networks:

- `lan-net`
- `wan-net`

## What This Lab Is Good Enough For

- keepalived / VRRP election drills
- VIP single-ownership checks
- bounded single-active service ownership
- promotion / demotion rehearsal
- safe topology debugging without touching the real homelab

## What This Lab Is Not Good Enough For

- physical NIC realism
- real ISP/WAN behavior
- PPPoE fidelity
- automatic DHCP failover proof
- BGP failover proof
- throughput benchmarking
- final production-grade HA claims

## Entry Points

The intended flow is:

1. build machine closures
2. create lab bridges
3. boot lab machines
4. run bounded assertions
5. destroy the lab

Scripts:

- `scripts/build-closures.sh`
- `scripts/create-bridges.sh`
- `scripts/boot-machines.sh`
- `scripts/run-scenario.sh`
- `scripts/destroy-lab.sh`

Scenario scripts:

- `scenarios/assert-vip-single-owner.sh`
- `scenarios/assert-single-active-demo-unit.sh`

## Notes

- The scripts currently target the `ha-basic` topology only.
- The raw `nspawn` harness is intentionally **not** part of `flake check`.
- Once the scenarios are stable, the best ones should be promoted into NixOS VM
  tests under `tests/`.
