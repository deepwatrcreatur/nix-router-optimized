# 31 - Router BGP Support Boundary and Docs

## Status: `in-progress`

## Objective

Make the support status of `services.router-bgp` explicit and discoverable so
the repo stops implying a stronger maturity level than the implementation
actually provides.

## Rationale

Discussion 05 concluded that BGP should stay in the flake, but should currently
be treated as an **advanced / experimental opt-in** rather than a broadly
supported router feature. The repo already exports the module and mentions it in
the README, so documentation needs to catch up to the real support boundary.

## Requirements

- [ ] Add `docs/router-bgp.md`
- [ ] Document:
  - what the wrapper currently does
  - the intended target user
  - the current limitations
  - operational verification steps for FRR/BGP peering
- [ ] Add at least one realistic BGP example that future users can adapt
- [ ] Update the BGP section in `README.md` to link to the dedicated doc
- [ ] Make the current support stance explicit in docs:
  - advanced / experimental opt-in
  - not yet validated as HA-ready

## Verification

- [ ] A contributor can find a dedicated BGP doc without reading module source
- [ ] README does not overstate BGP maturity
- [ ] The docs clearly distinguish current capability from future roadmap
- [ ] The docs explain how to verify a working BGP session operationally

## Notes

This is a docs-and-positioning item, not a claim that the underlying routing
capabilities are already complete.
