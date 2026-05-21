# 44 - Dashboard Inventory Browser Page and API

## Status: `done`

## Objective

Add a dedicated read-only inventory page to `router-dashboard`, backed by a
small API or static artifact path, so operators can browse hosts/IPs/subnets as
a first-class dashboard task.

## Rationale

Discussion 12 converged that inventory browsing is too large and too important
to squeeze into a small widget. The dashboard already has a page-oriented shell,
so the correct UI boundary is a dedicated `Inventory` page rather than an
overview badge or sidecar note.

## Requirements

- [x] Add a dedicated inventory browse surface to the existing dashboard shell
- [x] Expose inventory data to the frontend through a bounded read-only API
      endpoint or equivalent static artifact path
- [x] Support at least:
      - subnet grouping
      - host/IP search or filtering
      - host/detail display
      - clear labels that this surface is read-only
- [x] Keep the page visually and behaviorally aligned with the existing
      `router-dashboard` shell
- [x] Do not add any write/edit path for inventory state

## Verification

- [x] The dashboard exposes an explicit inventory page
- [x] Operators can answer “what host or IP is this?” and “what subnet does it
      belong to?” without leaving the dashboard
- [x] No mutable inventory action is introduced through the dashboard surface

## Notes

This item is about the **browse page and bounded data access path**.
Richer reconciliation states belong to follow-on work.

## Outcome

`router-dashboard` now ships an `Inventory` page backed by `/api/inventory`.
The page provides subnet grouping, host/IP filtering, host detail inspection,
and explicit read-only labeling while reusing the existing dashboard page shell.
Runtime reconciliation overlays remain deferred to item `45`.
