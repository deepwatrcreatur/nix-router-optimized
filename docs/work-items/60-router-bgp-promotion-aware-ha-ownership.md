# 60 - Router BGP Promotion-Aware HA Ownership

## Status: `done`

## Objective

Define and implement the minimum promotion-aware ownership model that would let
`router-bgp` coexist honestly with `router-ha` without implying that VRRP
failover automatically equals safe BGP failover.

The first slice should make the repo either:

- support a bounded single-active-owner BGP shape
- or continue to refuse the combination with more explicit rationale and tests

but not leave the question half-open.

## Rationale

The current module and docs are intentionally conservative:

- `router-bgp` is available
- `router-ha` exists
- but the repo does not yet have a promotion-aware routing ownership signal

That is the right safety stance today, but it leaves a real backlog gap:

- docs call out the missing ownership model
- the module message references the same limitation
- and incident/HA work elsewhere in the repo shows that ownership transitions
  are already an active systems concern

This item exists to make the boundary explicit and testable instead of letting
users infer support from adjacent HA features.

## Requirements

- [ ] Define the intended support stance for `router-bgp` with `router-ha`:
      - explicitly unsupported with stronger assertions and docs
      - or bounded supported with a single-active-owner model
- [ ] If bounded support is chosen, add the minimum declarative ownership signal
      and service behavior needed to answer:
      - when `bgpd` starts
      - when it must remain inactive
      - what identity/advertisement behavior is expected on standby nodes
- [ ] Add focused validation for the chosen boundary, including at least:
      - eval/assertion coverage for unsupported combinations
      - service/rendered-config checks for any supported owner-aware shape
- [ ] Update docs so operators can tell whether BGP+HA is refused, manual-only,
      or supportable in a narrowly defined topology

## Verification

- [ ] The repo no longer leaves `router-bgp` + `router-ha` as an ambiguous
      implied capability
- [ ] Unsupported shapes fail clearly, or supported bounded shapes have explicit
      owner-aware behavior and tests
- [ ] Docs describe the ownership transition boundary without equating VRRP and
      dynamic-routing control-plane ownership

## Notes

This item is about **promotion-aware ownership and support-boundary honesty**.

It should not expand into:

- full external-peering maturity work
- generic FRR clustering
- or broad routing-policy feature expansion unrelated to HA ownership
