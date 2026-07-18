# Router HA Lab Plan

This note records the current recommended plan for a **safe isolated HA
development lab** for `nix-router-optimized`.

It exists because recent live homelab failover work proved that the repo needs
a faster and safer inner loop than "change the real router and see what breaks."

The current validated production posture stays:

- one active router
- one cold/manual spare
- HA deferred in production until it can be developed and tested more safely

The lab described here is the next step toward that safer development path.

## Decision Summary

The repo should use a **small `systemd-nspawn` / NixOS-container lab as the
first HA development backend**.

This is a bounded engineering choice, not a claim that containers are the final
authority for router-grade failover realism.

`systemd-nspawn` is the right first investment because it gives:

- much faster iteration than full VMs
- direct reuse of the repo's NixOS module surfaces
- real `systemd`, `systemd-networkd`, keepalived, nftables, and service
  ownership behavior
- a way to rehearse failover logic without touching the real home network

What it does **not** give:

- physical-NIC realism
- hardware offload realism
- real ISP/WAN behavior
- full confidence in timing-sensitive or packet-pressure-dependent failover

So the intended staged model is:

1. use `nspawn` to learn and stabilize control-plane behavior
2. promote proven scenarios into NixOS VM tests
3. defer any stronger realism claims until a later validation layer exists

## What Phase 1 Should Prove

Phase 1 should answer only this:

> Can `nix-router-optimized` safely model and rehearse bounded HA ownership
> behavior without touching the real homelab?

That means proving:

- keepalived / VRRP election and VIP ownership in an isolated lab
- active vs standby service ownership boundaries
- promotion and demotion drills
- failover cleanup and non-split-brain assertions
- host-local isolation strong enough that the lab cannot interfere with the
  real LAN or WAN

Phase 1 is about **control-plane confidence**, not full data-plane realism.

## What Phase 1 Must Not Try To Prove

Keep these explicitly out of scope:

- real ISP interaction
- PPPoE behavior
- automatic Kea HA revival
- BGP failover
- multi-WAN
- hardware or driver offload behavior
- performance benchmarking
- full IPv6 PD realism
- Suricata / EveBox / dashboard restoration work
- production-grade HA claims

If the first slice tries to prove all of those at once, the lab will become too
slow, too ambiguous, and too hard to trust.

## First Topology

Start with one deliberately small topology:

- `router`
- `router-backup`
- `wan`
- `client`

Use two flat lab-only segments:

- `wan-net`
- `lan-net`

Expected behavior:

- `router` and `router-backup` both attach to `wan-net`
- `router` and `router-backup` both attach to `lan-net`
- `client` attaches to `lan-net`
- `wan` attaches to `wan-net`
- the VIP lives on `lan-net`
- `client` uses that VIP as its default gateway
- `wan` acts only as fake upstream next hop and reachability target

Keep the first topology flat. Do not start with:

- VLAN stacking
- multiple LAN segments
- bridges-on-bridges
- realistic home-inventory sprawl

## Mandatory Safety Boundaries

The lab must be unable to collide with the real homelab by design.

Required boundaries:

- no physical NIC attachment
- lab-only bridge, veth, namespace, unit, and state names
- no forwarding path from the lab into the real LAN or WAN
- documentation/test address space only
- host-level default-deny boundary for lab forwarding
- explicit create/destroy tooling that cleans up all lab state
- no requirement to mutate the host's production router settings to run the lab

Recommended naming pattern:

- `lab-` prefix for bridges and helper state
- topology-local names under `lab/nspawn/`
- one destroy path that can be run repeatedly without guessing what is stale

## Recommended Repo Layout

Keep the interactive lab separate from the CI/test surface at first.

Suggested structure:

- `lab/README.md`
- `lab/nspawn/`
- `lab/nspawn/topologies/ha-basic/`
- `lab/nspawn/machines/`
- `lab/nspawn/modules/`
- `lab/nspawn/scenarios/`
- `lab/nspawn/assertions/`
- `lab/nspawn/scripts/`

And one higher-level planning note:

- `docs/router-ha-lab-plan.md`

The intended boundary is:

- `lab/` for fast interactive design and rehearsal
- `tests/` for later deterministic VM regression coverage

## Recommended Scenario Order

Start with the smallest scenario that proves the core ownership model.

### Scenario 1: Clean boot

Prove:

- both routers boot
- exactly one becomes VRRP master
- VIP exists on one node only

### Scenario 2: Master failure

Prove:

- stopping keepalived or the active node causes the backup to take the VIP
- the VIP does not remain dual-owned

### Scenario 3: Single-active service boundary

Prove:

- a bounded single-active service starts on the intended owner
- it is absent or stopped on the standby

### Scenario 4: Manual DHCP promotion

Prove:

- the lab reflects the current repo truth that DHCP is not automatically
  failover-owned in the reference posture
- a deliberate promotion path can still be rehearsed safely

Do not add more scenarios until those four are trustworthy.

## Relationship To Later VM Tests

The `nspawn` lab should not become the permanent end state of regression
coverage.

Instead:

1. use it as the fast inner-loop lab
2. learn which scenarios are worth keeping
3. turn the stable ones into NixOS VM tests
4. use those VM tests as the durable regression gate in `flake check`

Good split:

- `nspawn`: scenario discovery, rehearsal, and debugging
- NixOS VM tests: deterministic regression protection

## Main Risks Of `nspawn`

The important limitations should stay explicit:

- shared host kernel means less realism than full VMs
- VRRP/L2 timing can differ from hardware or QEMU
- container cleanup mistakes can leave stale links and make results confusing
- container success can overstate confidence if readers forget the realism
  boundary

That is acceptable as long as the repo keeps the support boundary honest.

## Current Recommendation

Proceed with a **bounded `systemd-nspawn` phase-1 HA lab**.

Do not wait for a perfect full-VM harness before starting safer development.
But also do not pretend the lab proves more than it really proves.

The right engineering path is:

- small lab first
- explicit scope
- strong isolation
- later VM-test promotion

## Related Discussion

- [`discussions/18-router-ha-lab-backend-and-scope.md`](./discussions/18-router-ha-lab-backend-and-scope.md)
