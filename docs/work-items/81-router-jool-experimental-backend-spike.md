# 81 - Router Jool Experimental Backend Spike

## Status: `ready`

## Objective

Add a bounded, explicitly experimental Jool-backed NAT64 evaluation path that
uses the shared translation-backend surface without replacing Tayga as the
default supported backend.

Suggested branch: `feat/router-jool-spike`

## Rationale

The docs now make the repo stance explicit:

- `router-nat64` already exists today
- Tayga is the supported backend
- Jool is only a future evaluation candidate

Once item `80` lands, the repo will have the internal structure needed to test
that claim honestly instead of arguing from intuition.

This item exists to answer a bounded question:

- can Jool be expressed through the repo’s shared translation-backend contract
  without silently changing the operator-facing semantics?

It does **not** exist to declare Jool production-ready.

## Requirements

- [ ] Add an explicitly experimental Jool-backed evaluation path behind a clear
      non-default selector or spike surface
- [ ] Keep Tayga as the default supported backend
- [ ] Reuse the shared translation-backend adapter surface from item `80`
- [ ] Document any packaging, lifecycle, firewall, MTU, or observability gaps
      that prevent parity today
- [ ] Add bounded eval/docs/test coverage proving the Jool path is intentionally
      experimental rather than an accidental new default
- [ ] Make the README/docs language honest about what is and is not supported

## Verification

- [ ] A contributor can enable the Jool spike intentionally
- [ ] The Tayga path remains the default and still evaluates
- [ ] The repo records concrete parity gaps if Jool still falls short
- [ ] No docs imply that Jool is now the production recommendation unless the
      work actually proves that

## Notes

This item is about **evaluation and evidence**, not productizing Jool.

If the spike reveals that the shared contract is still incomplete, the right
outcome is to document the gap rather than force a misleading “supported”
surface.
