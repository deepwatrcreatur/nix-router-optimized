# 80 - Router NDPPD Support Boundary and First-Slice Contract

## Status: `ready`

## Objective

Turn Discussion 15 into an implementation-facing first-slice contract for a
bounded NDP proxy feature in `nix-router-optimized`.

This item should define what the repo is actually willing to support before any
module lands, so later implementation work does not accidentally turn
`ndppd` into a broader architecture promise than the discussion endorsed.

Suggested branch: `docs/router-ndppd-boundary`

## Rationale

Discussion 15 did **not** conclude that the repo should become a general NDP
toolbox.

The convergence was narrower:

- `ndppd` is the only honest near-term candidate
- the feature must remain advanced/opt-in
- the static `systemd-networkd` proxy path should be documented first
- HA ownership must be explicit rather than implied
- `ndpresponder` is deferred
- `ndproxy` and `ndp-proxy-go` are out of scope for the current Linux/NixOS
  flake boundary

This item exists to record that support boundary in repo-local docs and narrow
the first implementation slice before module code appears.

## Requirements

- [ ] Add a dedicated design/support doc for the first slice, such as
      `docs/router-ndp-proxy.md`, that states:
      - the intended user/problem shape
      - that the near-term backend is `ndppd`
      - that the feature is advanced/opt-in rather than a general default
- [ ] Document when operators should prefer the static
      `systemd-networkd` `IPv6ProxyNDP` / `IPv6ProxyNDPAddress` path instead of
      an NDP daemon
- [ ] Define the first supported topology concretely enough to guide later
      implementation, including at minimum:
      - one upstream interface
      - one or more downstream interfaces
      - Linux/NixOS router host
      - no claim of multi-active HA behavior
- [ ] Make the exclusions explicit in docs:
      - `ndpresponder` is deferred pending packaging/support review
      - `ndproxy` is not a coherent supported target here
      - `ndp-proxy-go` is outside the repo's platform boundary
- [ ] Describe the HA ownership rule the later module must obey:
      - single-active owner only
      - no silent dual-active proxy replies
      - assertion-driven refusal for ambiguous `router-ha` combinations
- [ ] Leave the design specific enough that a later module PR does not have to
      invent the support boundary from scratch

## Verification

- [ ] A contributor can read one repo-local doc and tell:
      - whether NDP proxying is in scope at all
      - which backend is the actual near-term candidate
      - when the static networkd path is sufficient
      - and why the other named tools are not being exposed now
- [ ] The first-slice topology and HA ownership rule are concrete enough to drive
      assertions and service behavior later
- [ ] The docs do not imply that all NDP proxy tools are equivalent or currently
      supported

## Notes

This is a **boundary-and-contract** item first.

It should not silently implement the full module as part of the same PR.
