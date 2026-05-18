# 38 - Router CLAT First-Slice Contract and Assertions

## Status: `done`

## Objective

Turn the declarative CLAT direction into an implementation-ready **first-slice
contract** without yet treating a live translation service as the main task.

This item exists to define the bounded topology, DNS behavior, mapping
semantics, backend artifact shape, and assertion model that any later
`router-clat` implementation must obey.

## Rationale

Discussion 09 concluded that `docs/DECLARATIVE_CLAT.md` is directionally right
but still underspecified in router-grade ways.

The strongest convergence was that the next step should **narrow the contract**
before implementation pressure turns Tayga or any other backend into the
accidental architecture.

The panel specifically called out the need to define:

- supported first-slice topology
- route ownership and conflict behavior
- DNS behavior and DNS-service ownership/integration
- mapping refresh / expiry semantics
- failure behavior
- observability expectations
- deterministic backend artifact generation

## Requirements

- [x] Define the supported first-slice topology explicitly, including what is
      intentionally unsupported in the first slice:
      - active-owner assumptions
      - upstream/downstream interface shape
      - multi-WAN boundary
      - HA boundary
      - asymmetric-routing boundary
- [x] Define the route ownership and conflict model concretely enough to drive:
      - NixOS assertions
      - startup refusal when the topology is ambiguous
      - coexistence with `router-nat64`, `router-firewall`, and host routing
- [x] Define the DNS behavior contract for the first slice, including:
      - whether `router-clat` owns a DNS listener, depends on another DNS service,
        or integrates with one optionally
      - behavior for AAAA-only, A-only, dual-stack, NXDOMAIN, and NODATA answers
      - TTL handling and any synthesis constraints
- [x] Define the persistent mapping record shape and authoritative fields,
      including:
      - how mappings are keyed
      - what refreshes `lastSeen` / `lastUsed`
      - what expiry means for active or long-lived flows
      - how multiple AAAA answers are handled
- [x] Define a deterministic backend artifact schema that is not Tayga-shaped in
      public semantics even if Tayga is the first backend target
- [x] Define minimum failure behavior and observability expectations for the
      first slice:
      - fail-closed vs partial-success boundaries
      - required status surfaces
      - required logs / rejection reasons / inspection paths
- [x] Update `docs/DECLARATIVE_CLAT.md` so the first-slice contract is explicit
      enough to guide implementation without relying on implied runtime behavior
- [x] Identify the smallest validation surface for this contract work, such as:
      - assertion/eval checks
      - deterministic config-generation tests
      - dry-run or fixture-driven mapping tests

## Verification

- [x] A contributor can read the design docs and tell exactly what the first
      supported topology is
- [x] The route/conflict model is concrete enough that later module code can
      reject ambiguous ownership instead of guessing
- [x] The DNS contract is explicit enough that a later implementation will not
      silently conflict with existing DNS services
- [x] The mapping record/backend artifact boundary is documented independently of
      Tayga's specific runtime behavior
- [x] The first-slice support boundary is explicit about failure modes and
      observability expectations

## Notes

This item is intentionally **pre-runtime** in emphasis.

The goal is not to ship a mostly-working translator quickly. The goal is to make
the first eventual runtime slice safer and more honest by defining the contract
first.

Discussion 09 is the immediate evidence base for this item:
`docs/discussions/09-declarative-clat-design-review-and-first-slice-boundary.md`.

This item is complete once the design doc carries enough implementation-facing
contract detail that a later runtime slice can be scoped without guessing at
topology, DNS semantics, mapping identity, backend artifact shape, or failure
policy.
