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

## Runtime Status

As of July 22, 2026, the live local rehearsal has advanced beyond the original
scaffold boundary and now passes the bounded phase-1 assertions end to end:

- the harness now builds bootable LXC rootfs tarballs rather than trying to
  point `systemd-nspawn` at `config.system.build.toplevel`
- the guest boot path works with the lab-only runtime compatibility overrides
  for `dbus`, `dbus-broker`, and `systemd-networkd`
- the scenario transport uses `nsenter` rather than `machinectl shell`
- the lab now uses explicit host/guest veth handoff with
  `--network-interface=...:hostN`
- the bounded scenario flow
  (`destroy-lab` -> `create-bridges` -> `boot-machines` -> assertions) passes
  from a cold start

This means the lab is exercising a real boot path and a real control-plane
rehearsal path, not only eval-time topology wiring.

## Known Issues

The first live `nspawn` rehearsal also exposed important backend-specific
constraints that remain part of the current design:

- the host must disable bridge netfilter for the lab bridges while the harness
  is active (`bridge-nf-call-iptables/ip6tables/arptables = 0`), otherwise
  guest-to-guest LAN delivery is broken even though VRRP/ICMP frames appear on
  the host-side veths; these sysctls are host-global, so the lab should only
  be run on an isolated development host or under an operator-approved
  precondition that temporarily changing host bridge-netfilter behavior will
  not interfere with other bridge users
- precreated veths need an explicit settle step before `systemd-nspawn`
  accepts them via `--network-interface`
- extracted LXC roots can contain immutable paths such as `/var/empty`, so
  rerun cleanup must handle those paths deliberately

So the harness is now a working runtime runner for the current bounded phase-1
scenarios, but it should still be treated as a backend-specific lab surface
rather than as a general proof of production-grade HA behavior.
