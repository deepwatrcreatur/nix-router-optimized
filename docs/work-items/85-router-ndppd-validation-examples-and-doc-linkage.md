# 85 - Router NDPPD Validation, Examples, and Doc Linkage

## Status: `done`

## Objective

Add the smallest honest validation and operator-facing example/documentation
surface for the new `ndppd` first slice so the repo does not expose the module
without showing how to verify and use it safely.

Suggested branch: `test/router-ndppd-validation`

## Rationale

Discussion 15 did not just call for a module.
It also converged on two operational points:

- operators need help distinguishing the static networkd path from the dynamic
  daemon path
- and HA/single-owner behavior must be explicit and testable, not left as prose

Once the module exists, the repo still needs a small but real validation and
example surface so contributors and consumers can tell:

- what a supported config looks like
- what combinations are intentionally refused
- and how to confirm that the repo's docs match actual eval behavior

## Requirements

- [x] Add focused validation for the new module, including at minimum:
      - successful eval for a bounded standalone configuration
      - assertion/failure coverage for unsupported or ambiguous HA combinations
      - any minimal config-render checks needed to prove deterministic output
- [x] Add at least one example configuration for the supported first slice
- [x] Add or update docs so the README/module docs point readers to:
      - the dedicated NDP proxy doc
      - the example configuration
      - and the support-boundary stance
- [x] Ensure the docs explain how an operator can verify the resulting service
      and configuration rather than assuming the feature is self-evident
- [x] Keep the validation focused on the declared first slice instead of trying
      to simulate every possible IPv6 topology

## Verification

- [x] A contributor can find one example and one dedicated doc without reading
      module source
- [x] CI/local eval coverage proves that supported and refused shapes behave as
      the docs claim
- [x] The README and dedicated docs do not overstate maturity or backend scope

## Notes

This item is intentionally **post-module** in emphasis.

It should land after the support contract and bounded module shape are in place,
not as a substitute for either of them.
