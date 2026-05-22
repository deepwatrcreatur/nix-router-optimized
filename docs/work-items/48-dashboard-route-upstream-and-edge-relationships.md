# 48 - Dashboard Route Upstream and Edge Relationships

## Status: `ready`

## Objective

Add a browse-only router edge/relationship layer to the inventory surface so the
dashboard can explain how interfaces, prefixes, gateways, peers, and overlay
links fit together.

The bounded goal is to make routing and segment relationships legible, not to
build a full topology editor.

## Rationale

Once interface/prefix detail and DHCP/neighbor reconciliation exist, the next
operator question is usually relational:

- which upstream/gateway serves this segment
- which interface carries this prefix
- where this route points
- which overlay or peer link is associated with this edge
- and what the router currently believes the active path is

The current dashboard has status widgets and the inventory browser has basic
browse/reconciliation foundations, but there is still a gap between “here are
objects” and “here is how the network is stitched together.”

This item is where the router inventory surface should borrow NetBox-like
cross-linking and contextual detail panels while staying honest about being a
derived read-only view.

## Requirements

- [ ] Extend the browse model to expose bounded relationship views for at least:
      - interfaces to prefixes
      - prefixes to gateways / routes
      - upstream / WAN edges
      - overlay or peer interfaces where already modeled in the repo
- [ ] Add a route/gateway or edge-oriented browser view that helps answer:
      - what is this segment's upstream
      - what route owns this destination
      - which interface is carrying this path
- [ ] Reuse existing dashboard shell/navigation and make relationship views
      cross-link cleanly with inventory, status, and module-specific surfaces
- [ ] Make provenance and confidence explicit where relationships are inferred
      rather than directly declared
- [ ] Keep the result text/table/detail oriented; do not require a graphical
      topology canvas for the first slice

## Verification

- [ ] An operator can browse from an interface or prefix to its relevant
      route/gateway/upstream context
- [ ] The dashboard can distinguish clearly declared relationships from runtime
      inference or observation
- [ ] The first slice improves router troubleshooting without introducing
      configuration mutation through the UI
- [ ] The resulting relationship view remains small, inspectable, and consistent
      with the repo's declarative authority model

## Notes

This item is about **relationship legibility** for router inventory.

It should not expand into:

- a full graphical topology tool
- route editing or failover control from the dashboard
- or a generalized external CMDB model

If a richer topology view is wanted later, it should grow from these bounded
relationship read models rather than from an independent mutable canvas.
