# 46 - Dashboard Interface and Prefix Detail Surface

## Status: `ready`

## Objective

Deepen the existing read-only inventory browser so it works like a router
networking inventory surface rather than only a host/IP lookup page.

The next slice should make the dashboard genuinely useful for browsing:

- interfaces
- assigned addresses
- bridges / VLAN attachments
- prefix membership
- and interface-to-prefix relationships

without turning the dashboard into a mutable network-management authority.

## Rationale

Items `43` through `45` established the bounded first slice:

- a canonical read-only inventory export
- a dedicated `Inventory` page
- and simple declared-vs-runtime reconciliation plus subnet summary

That was the right first step, but the maintainer clarified that the stronger
target is specifically **router networking inventory browsing**.

For that use case, the center of gravity is not generic host inventory. It is:

- which interface owns what
- which prefixes live where
- what addresses are assigned
- and how router-local network objects relate to each other

The strongest NetBox idea worth borrowing here is its object-detail rhythm and
cross-linking, not its mutable CMDB model.

## Requirements

- [ ] Extend the dashboard inventory data contract to expose interface-centric
      read models sufficient for browsing at least:
      - interface name / kind
      - operational role if declared
      - assigned IPv4 / IPv6 addresses
      - bridge / VLAN attachment if declared
      - subnet / prefix membership
      - provenance markers
- [ ] Add a dedicated interface-focused browser surface or detail drill-down
      within the existing inventory page shell
- [ ] Add prefix/detail drill-down that makes it easy to answer:
      - what addresses are declared in this prefix
      - which interface or segment this prefix belongs to
      - what reservations / live leases are associated with it
- [ ] Reuse existing dashboard page/navigation patterns instead of creating an
      unrelated second admin UI
- [ ] Keep the entire surface explicitly read-only and derived from declarative
      config plus already-approved bounded runtime overlays

## Verification

- [ ] An operator can answer “what is on this interface?” without reading raw Nix
      or shell output
- [ ] An operator can open a prefix and quickly understand its declared role,
      membership, and related addresses
- [ ] The UI makes interface/prefix relationships legible through links, badges,
      or compact summary panels rather than forcing raw JSON inspection
- [ ] No edit path or mutable inventory authority is introduced

## Notes

This item is about **interface/prefix-first browse depth**.

It should not expand into:

- write/edit controls for network state
- topology drawing for its own sake
- or broad enterprise IPAM/DCIM modeling that the repo does not declare

Later work can build on this to show routes, gateways, live neighbors, and
deeper edge relationships.
