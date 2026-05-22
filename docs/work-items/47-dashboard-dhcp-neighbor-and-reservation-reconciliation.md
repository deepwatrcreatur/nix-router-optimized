# 47 - Dashboard DHCP Neighbor and Reservation Reconciliation

## Status: `ready`

## Objective

Extend the router inventory browser so it answers the concrete operational
questions that come up on a live router:

- who currently has this IP
- which addresses are reserved vs dynamically leased
- whether a live client matches its declared reservation
- and whether a host exists only in runtime neighbor/lease state

while preserving the existing declarative authority boundary.

## Rationale

Item `45` added bounded reconciliation states and subnet summary cues, but the
router-specific browsing target suggests a richer next slice centered on
runtime networking evidence:

- DHCP reservations
- active leases
- ARP / NDP neighbor visibility
- MAC-to-IP association
- and conflict / drift cues

This is the router equivalent of the “what host is this?” question, but sharpened
to the problems a gateway operator actually sees during debugging.

The goal is not a mutable IPAM or lease-management console. The goal is a
better read-only explanation of how declared router intent and live client state
line up.

## Requirements

- [ ] Extend the inventory/reconciliation model to represent at least:
      - declared reservations
      - active DHCP leases
      - runtime-only neighbors
      - reservation mismatches / conflicts
      - provenance for each state
- [ ] Surface MAC address, lease age/expiry where available, and subnet/context
      links in a way that is easy to browse from the inventory UI
- [ ] Add filters or badges for states such as:
      - reserved
      - leased
      - runtime-only
      - conflict
      - stale / expired where derivable
- [ ] Make it possible to drill from a subnet or interface view into the
      reservations / leases / neighbors associated with that network segment
- [ ] Keep the result explicitly read-only and derived from existing router
      runtime sources plus declarative config

## Verification

- [ ] An operator can answer “who has this address right now?” from the dashboard
- [ ] An operator can quickly distinguish declared reservations from transient
      runtime clients
- [ ] Conflicts or mismatches are visible without requiring manual comparison of
      multiple raw sources
- [ ] The resulting surface still does not become a DHCP or IPAM editing console

## Notes

This item is about **runtime reconciliation depth for router inventory**.

It should not expand into:

- lease editing or forced reassignment from the UI
- mutable reservation management
- or general-purpose device lifecycle tracking outside router-relevant evidence

The strongest design pattern to borrow is compact status coloring and
cross-linked detail, not backend mutability.
