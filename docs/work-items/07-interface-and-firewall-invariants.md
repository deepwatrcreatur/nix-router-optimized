# 07 Interface And Firewall Invariants

Status: `in-progress`

Suggested branch: `feat/router-interface-firewall-invariants`

## Goal

Encode the router flake’s interface- and firewall-related assumptions in tests
or assertions so downstream users do not discover breakage only during deploys.

## Why This Matters

Several modules derive behavior from interface roles or optional ownership by
`router-firewall` and `router-optimizations`. Those assumptions are useful, but
they are currently implicit and under-tested.

## Scope

- identify the most important shared derivations, such as:
  - WAN interface derivation
  - trusted interface wiring
  - firewall-exposed ports from wrapper modules
- add checks or assertions that make these invariants explicit
- prefer fast evaluation checks first

## Candidate Invariants

- if a module exposes WAN traffic, it must have a clear source of WAN interfaces
- optional firewall integration must not hard-fail when the firewall module is
  absent
- router modules must continue to evaluate when only `router-optimizations`
  provides interface structure
- trusted-interface assumptions should remain explicit rather than hidden in
  string concatenation or ad hoc defaults

## Non-Goals

- rewriting the module architecture in the same PR
- a full firewall behavior simulation

## Validation

- at least one CI-visible check covers shared interface derivation
- at least one CI-visible check covers optional firewall composition
