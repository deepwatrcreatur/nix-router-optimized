# 32 - Router BGP Firewall and Validation

## Status: `done`

## Objective

Bring `router-bgp` into line with this repo's module-authoring conventions for
optional firewall integration and focused eval coverage.

## Rationale

Discussion 05 found that the current module is technically usable, but does not
yet meet the same maturity bar as other router wrappers. The most immediate
implementation cleanup is to respect `router-firewall` when present and improve
validation so the module's behavior is less implicit.

## Requirements

- [x] Update `modules/router-bgp.nix` to integrate with `router-firewall` when it
      is imported and enabled
- [x] Keep native `networking.firewall` fallback when `router-firewall` is not
      present
- [x] Preserve import safety when optional peer modules are absent
- [x] Add focused eval coverage for:
  - standalone BGP enablement
  - BGP with `router-firewall`
  - any new assertions or defaults added by this change
- [x] Add or validate a repo example that exercises the supported configuration
      shape

## Verification

- [x] `router-bgp` opens TCP `179` through the appropriate firewall path
- [x] The module still evaluates cleanly without `router-firewall`
- [x] New eval checks are exported from `tests/default.nix`
- [x] The example/doc configuration remains eval-safe

## Notes

This is the "module contract" cleanup item for BGP. It should stay narrow and
not absorb the larger HA or route-policy roadmap.
