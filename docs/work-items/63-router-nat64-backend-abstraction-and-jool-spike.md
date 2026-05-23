# 63 - Router NAT64 Backend Abstraction and Jool Spike

## Status: `ready`

## Objective

Make the repo's NAT64 / "PLAT-side" story explicit and backend-neutral enough
to evaluate Jool without silently replacing the current Tayga-backed path.

This item should:

- state clearly that `router-nat64` is the repo's current PLAT-equivalent
  surface
- define the backend contract that `router-nat64` and `router-clat` actually
  rely on
- and add a bounded Jool spike only if that contract is explicit enough to keep
  Tayga as the supported default

## Rationale

The repo now has:

- a Tayga-backed `router-nat64` module for NAT64
- and a Tayga-backed experimental `router-clat` slice for the customer-side
  translation story

That means the project is not missing the PLAT half in practice, but it is
still too Tayga-shaped internally:

- CLAT tests inspect `tayga.conf`
- service names are Tayga-specific
- runtime assumptions are not yet presented as a backend contract

Jool is a plausible future backend, but swapping it in directly would entangle:

- operator docs
- firewall/runtime assumptions
- observability surfaces
- and CLAT/NAT64 implementation details

This item exists to separate "evaluate Jool" from "accidentally make Tayga an
unspoken permanent ABI."

## Requirements

- [ ] Update docs / README surfaces so the current state is explicit:
      - `router-nat64` is the repo's present PLAT-equivalent path
      - `router-clat` is the customer-side translation slice
      - the current end-to-end story is Tayga-backed and not yet backend-neutral
- [ ] Define the minimum backend contract that a NAT64 engine must satisfy for
      this repo, including at least:
      - address/prefix inputs
      - interface/runtime lifecycle expectations
      - firewall integration points
      - observability/status surfaces
      - artifact/config surfaces that are allowed to stay backend-specific vs
        those that must become abstract
- [ ] Decide whether backend selection belongs:
      - only in `router-nat64`
      - in both `router-nat64` and `router-clat`
      - or behind a shared translation-backend contract
- [ ] Add a bounded Jool spike only if it stays explicitly experimental and does
      not silently replace Tayga as the default supported path
- [ ] Ensure any Jool path is described as a spike / evaluation path unless and
      until parity, packaging, and operational support are proven

## Verification

- [ ] A contributor can read the repo and tell that NAT64/PLAT already exists
      today via `router-nat64`
- [ ] The repo has an explicit translation-backend boundary rather than treating
      Tayga-specific files and unit names as the public contract
- [ ] If a Jool path lands, it is selectable intentionally and surfaced as
      experimental rather than implied default behavior
- [ ] If no Jool path lands yet, the repo still records the contract and the
      rationale for keeping Tayga as the current supported backend

## Notes

This item is about **backend abstraction and an evidence-first Jool spike**.

It should not pretend that:

- NAT64/PLAT is currently absent
- Jool is automatically better just because it is kernel-space
- or CLAT/NAT64 backend replacement is a one-file implementation swap
