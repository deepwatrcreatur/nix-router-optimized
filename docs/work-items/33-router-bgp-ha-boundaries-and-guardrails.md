# 33 - Router BGP HA Boundaries and Guardrails

## Status: `in-progress`

## Objective

Define and enforce a safe boundary between `router-bgp` and the repo's HA /
promotion model so BGP is not accidentally treated as failover-ready before
single-active-owner semantics are explicit.

## Rationale

Discussion 05 concluded that HA interaction is the biggest architectural warning
for BGP in this repo. The HA work is already moving toward "shared capability,
single active owner." BGP needs an explicit position inside that model.

## Requirements

- [ ] Decide the short-term support policy for `router-bgp` + `router-ha`:
  - hard assertion
  - explicit warning/documented incompatibility
  - or gated ownership if the required active-owner signal already exists
- [ ] Ensure the chosen policy is encoded in repo docs and module behavior
- [ ] Prevent the repo from implying that two HA peers can both own active BGP
      routing identity casually
- [ ] Add targeted eval coverage for the chosen guardrail behavior
- [ ] Document what future promotion-aware BGP ownership would need

## Verification

- [ ] The combined BGP/HA story is explicit rather than implicit
- [ ] Future contributors can tell whether the combo is blocked, warned, or
      gated
- [ ] Eval/tests cover the intended guardrail

## Notes

This item is about support boundaries first. Full promotion-aware BGP behavior
may still depend on broader HA ownership work elsewhere in the stack.
