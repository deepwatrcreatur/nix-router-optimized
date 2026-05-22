# 49 - DHCP Option 108 Support Boundary and Docs

## Status: `done`

## Objective

Define the support boundary for RFC 8925 / DHCPv4 option `108`
(`IPv6-Only Preferred`) in `nix-router-optimized` so the repo can expose the
feature honestly without implying that every DHCP backend or every LAN should use
it.

## Rationale

The repo already has the pieces needed for IPv6-mostly deployments:

- `router-nat64`
- `router-dns64`
- multiple DHCP backends with different capability surfaces

Option `108` is only useful in a narrower scenario:

- the LAN is intentionally IPv6-mostly / IPv4-on-demand
- NAT64 (and usually DNS64) actually works
- the operator wants IPv6-capable clients to avoid consuming IPv4 leases

That means the first task is not “just add one more DHCP knob.” The first task
is to define:

- when the feature is appropriate
- which backend(s) should support it
- what preconditions must hold
- and which defaults would be misleading or too risky

## Requirements

- [x] Add a dedicated documentation/update pass covering RFC 8925 option `108`
      and how it relates to:
      - `router-nat64`
      - `router-dns64`
      - IPv6-mostly / IPv4-on-demand LANs
      - mixed client compatibility expectations
- [x] Document an explicit support stance for each DHCP backend:
      - `router-kea`
      - `router-dhcp`
      - `router-technitium`
- [x] Make it explicit that option `108` is:
      - advanced / opt-in
      - not a default for ordinary dual-stack LANs
      - and not a substitute for CLAT
- [x] Update the most relevant docs (at least `DHCP_SELECTION.md` and the
      NAT64/DNS64 docs) to explain when operators should and should not use it

## Verification

- [x] A user can tell from docs whether option `108` is supported on their chosen
      DHCP backend
- [x] The repo does not imply that enabling NAT64 alone means option `108` should
      also be turned on automatically
- [x] The docs clearly distinguish IPv6-mostly / IPv4-on-demand from generic
      dual-stack DHCP service

## Notes

This is the support-boundary and operator-guidance item.

It should not absorb:

- all backend implementation work
- extensive client compatibility research across every OS
- or a default-on policy decision

Those belong to follow-on implementation and validation items.
