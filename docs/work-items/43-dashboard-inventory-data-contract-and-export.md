# 43 - Dashboard Inventory Data Contract and Export

## Status: `pending`

## Objective

Define and export a canonical read-only inventory data model for
`router-dashboard` so the dashboard can browse the repo-native authority surface
without inventing a second mutable database.

## Rationale

Discussion 12 concluded that:

- inventory browsing is now worth doing
- literal `phpIPAM` code reuse is the wrong move
- the first slice should be repo-native and read-only

That means the dashboard needs a stable reduction layer between declarative Nix
inventory and frontend rendering. The browser page should not parse scattered
Nix/runtime facts ad hoc in the frontend.

## Requirements

- [ ] Define a normalized inventory shape for dashboard consumption covering at
      least:
      - subnets
      - hosts / labels
      - reserved addresses
      - available source/provenance markers
- [ ] Export that shape as a deterministic JSON artifact or equivalent
      read-only runtime data source
- [ ] Keep the exported data explicitly non-authoritative:
      it is a reduction of repo-native truth, not a writable state store
- [ ] Document how the export relates to the existing declarative inventory
      surface
- [ ] Avoid coupling the reusable dashboard surface to an ad hoc private schema
      beyond what is needed for the current bounded slice

## Verification

- [ ] A single inspectable inventory artifact is produced for dashboard use
- [ ] The artifact is reproducible from configuration and does not require a
      mutable database
- [ ] The data contract distinguishes declared information from runtime-derived
      overlays cleanly enough for later reconciliation work

## Notes

This item is about the **inventory reduction contract**, not yet the final
browser UI.
