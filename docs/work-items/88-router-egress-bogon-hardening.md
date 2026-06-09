# 88 - Router Egress Bogon Hardening

## Status: `in-progress`

## Objective

Add a bounded nftables hardening slice that blocks WAN egress traffic destined
to bogon / special-purpose IPv4 ranges, covering both forwarded traffic and
router-originated traffic.

Suggested branch: `feat/router-egress-bogon-hardening`

## Rationale

Discussion 16 found that the OpenBSD router has one small but meaningful
defensive measure that is not yet clearly present here:

- explicit outbound bogon blocking on WAN

`nix-router-optimized` already has substantial hardening work:

- kernel/network tuning
- Geo-IP controls
- MAC security
- router-firewall extension points

But explicit WAN egress blocking to reserved/unroutable IPv4 destinations is
still a useful and bounded additional measure.

This is attractive because it is:

- small in surface area
- easy to reason about
- and straightforward to test at eval / generated-ruleset level

## Requirements

- [x] Decide whether this belongs in:
      - `router-security-hardened`
      - `router-firewall`
      - or a narrowly shared boundary between them
- [x] Add an option shape for the behavior rather than silently hardcoding it
- [x] Define the initial IPv4 bogon/special-purpose range set explicitly
- [x] Cover both:
      - forwarded LAN-to-WAN traffic
      - and router-originated WAN egress
- [x] Ensure the resulting rules are scoped to WAN egress rather than generic
      local traffic
- [x] Add focused eval or generated-ruleset coverage
- [x] Update docs if the option becomes operator-visible

## Verification

- [x] Generated nftables rules include the bogon set and the intended egress drop
      rules only when the option is enabled
- [x] The change does not regress existing firewall composition points
- [x] A reviewer can tell the difference between this feature and existing
      inbound Geo-IP or rp_filter-style hardening

## Notes

Keep this item narrow.

It is not a general redesign of `router-security-hardened`, and it should not
expand into dynamic threat-feed work.
