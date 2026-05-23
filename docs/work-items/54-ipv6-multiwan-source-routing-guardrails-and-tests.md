# 54 - IPv6 Multi-WAN Source-Routing Guardrails and Tests

## Status: `done`

## Objective

Add the missing guardrails and validation surface for IPv6 multi-WAN so the repo
does not encourage multi-uplink IPv6 configurations that silently violate source
prefix / uplink correctness.

## Rationale

Round 125 converged that the main IPv6 multi-WAN risk is not just missing
features but **source-address correctness**:

- a client can pick an address from WAN A's prefix
- while traffic exits WAN B
- and upstream ingress filtering then drops it

The repo already has relevant primitives:

- policy-routing hooks
- PvD support
- NPTv6

But there is still a gap between “primitives exist” and “the supported shape is
hard to misuse.” This item exists to close that gap for the first serious IPv6
multi-WAN slice.

## Requirements

- [x] Review the current IPv6 multi-uplink shapes and add assertions, warnings,
      or guidance where obviously unsafe combinations are easy to express
- [x] Add focused tests or eval-time validation around at least:
      - source-based policy-routing precedence
      - multi-prefix / uplink interaction where relevant
      - NPTv6 coexistence with multi-uplink routing expectations
- [x] Make the operator-visible boundary explicit for configurations that remain
      advanced/manual rather than fully guarded
- [x] If the repo already has enough information to generate or validate safer
      source-based routing defaults, document or implement that narrow guardrail

## Verification

- [x] The repo has at least one concrete validation surface covering IPv6
      multi-WAN source/uplink correctness
- [x] Unsafe or unsupported combinations fail more clearly than they do today
- [x] The resulting tests/docs make the IPv6 multi-WAN support boundary more
      trustworthy and less guess-based

## Notes

This item is about **guardrails and correctness validation**, not about building
an all-encompassing IPv6 multi-WAN policy engine.

It should stay focused on the highest-risk correctness traps surfaced by the
round.
