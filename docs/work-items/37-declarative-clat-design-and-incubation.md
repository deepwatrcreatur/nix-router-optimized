# 37 - Declarative CLAT Design and Incubation

## Status: `in-progress`

## Objective

Define and incubate a **repo-native, declarative** CLAT-style capability for
legacy IPv4-only clients reaching IPv6 destinations, using `styx46` only as
inspiration and reference material rather than as the implementation shape to
wrap directly.

## Rationale

Discussions 07 and 08 concluded that:

- the underlying problem is conceptually in scope for `nix-router-optimized`
- `styx46` demonstrates a useful direction
- but the current upstream is too operationally sharp to become the repo's
  first-class model:
  - no mapping timeout
  - direct sysctl mutation
  - direct Tayga ownership
  - route ownership assumptions
  - explicit upstream non-production disclaimer

The maintainer has now made the intended direction explicit:

- the project is **not** primarily trying to ship this exact feature
  immediately
- this should instead be treated as a test of the repo's design council and
  implementation discipline
- the resulting capability should be **repo-native and declarative from day one**
- and the larger project identity should be:
  turning sharp router prototypes into clean Nix-native capabilities

## Requirements

- [x] Write a design / RFC document for a repo-native CLAT-style capability that
      clearly distinguishes:
      - the user problem
      - what is borrowed conceptually from `styx46`
      - what must be rethought to fit repo and NixOS idioms
- [x] Define the intended module boundary and naming shape for the future
      capability without prematurely promising implementation maturity
- [x] Specify a declarative state / lifecycle model for:
      - mapping allocation
      - mapping expiry / garbage collection
      - Tayga interaction or alternative translation data plane
      - route ownership
      - sysctl ownership
      - firewall ownership
- [x] Specify coexistence and conflict rules with existing modules, especially:
      - `router-nat64`
      - `router-dns64`
      - `router-firewall`
      - future HA / active-owner boundaries
- [x] Define what should remain repo-local versus what, if anything, could be
      contributed upstream to the original project or related upstreams
- [x] Plan explicit council/discussion checkpoints during implementation so the
      feature remains a live design exercise rather than a silent branch rewrite
- [x] Identify the smallest useful first implementation slice that proves the
      design without overclaiming readiness

## Verification

- [x] A contributor can read the resulting design doc and understand why the repo
      is not doing a naïve wrapper
- [x] The intended control-plane / data-plane split is explicit enough to guide
      implementation work
- [x] The design names concrete ownership rules for routes, sysctls, firewall,
      and runtime state
- [x] The roadmap makes room for iterative discussion rounds as implementation
      develops
- [x] The repo's support boundary is explicit before any implementation is
      presented as a normal router feature

## Notes

This item is intentionally **design-first**. The immediate goal is not to
maximize short-term feature delivery, but to test whether the project can take a
sharp but interesting router prototype and turn it into a clean, credible,
Nix-native design effort that invites further contribution.

Initial design artifact drafted in `docs/DECLARATIVE_CLAT.md`. Follow-on
implementation work should proceed through further discussion checkpoints rather
than treating the design as frozen.
