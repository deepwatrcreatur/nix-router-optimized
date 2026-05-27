# 52 - Router Multi-WAN Positioning and Doc Boundary

## Status: `done`

## Objective

Align the repo's user-facing language around multi-WAN so `nix-router-optimized`
clearly promises what it actually offers today:

- IPv4 failover / prioritized uplinks as the normal product
- and not a broad, polished "load-balancing" story

## Rationale

Round 125 converged that the repo should not present IPv4 and IPv6 multi-WAN as
symmetrical features.

The current implementation already supports a supportable IPv4-first story:

- `router-mwan` health checks
- metric-based failover / priority switching
- WAN HA / MAC-cloning adjuncts in the broader router story

The main risk now is documentation drift:

- users hear "multi-WAN" and expect bonding or aggregate throughput
- while the current module is actually a failover / prioritized-uplink mechanism

This item exists to tighten that boundary before more advanced routing features
are added.

## Requirements

- [x] Update the relevant docs and README surfaces so `router-mwan` is described
      as:
      - failover
      - prioritized uplinks
      - optional selected policy-routing companion patterns
      - and **not** generic load balancing
- [x] Add at least one explicit note describing unsupported expectations such as:
      - aggregate throughput
      - connection-preserving failover
      - ECMP-like balancing
      - state-synchronized HA behavior
- [x] Add or refine an example for the standard supported shape:
      - primary WAN
      - secondary WAN
      - health-check driven metric switching
- [x] Ensure any future advanced balancing direction is referred to separately
      rather than widening the apparent meaning of `router-mwan`

## Verification

- [x] A user reading the repo docs can tell what `router-mwan` actually does
- [x] README no longer implies a broader polished balancing story than the module
      supports
- [x] The default/example configuration reflects prioritized failover, not ECMP

## Notes

This item is about **positioning, examples, and support boundary honesty**.

It should not absorb implementation of advanced balancing modes. If those ever
land, they should do so as separate explicitly advanced work.

## Outcome

- Added [`docs/router-mwan.md`](../router-mwan.md) as the durable user-facing
  boundary document for prioritized uplink failover.
- Updated README wording so `router-mwan` is described as failover /
  prioritized-uplink behavior instead of a generic balancing story.
- Added an explicit standard example with primary WAN, backup WAN, and
  health-check driven metric switching.
- Recorded unsupported expectations explicitly:
  - aggregate throughput
  - ECMP-like balancing
  - connection-preserving failover
  - state-synchronized HA behavior
