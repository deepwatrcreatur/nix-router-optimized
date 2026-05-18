# 35 - Router Zones Composition Reset

## Status: `in-progress`

## Objective

Reset `router-zones` to a composition model that is correct, explicit, and safe
with `router-firewall` before adding more feature surface to the module.

## Rationale

Discussion 06 concluded that the recent repo direction is mostly good, but that
`router-zones` is the one reviewed area where ordinary cleanup may no longer be
enough. The main concerns are:

- risky or invalid nft rendering around policy rendering
- input-path behavior that may preempt or override base `router-firewall`
  semantics instead of composing with them
- a support boundary that is currently too easy for users to misunderstand

## Requirements

- [x] Decide and document the composition contract between `router-zones` and
      `router-firewall`
- [x] Ensure zone handling does not silently preempt base router-local policy in
      unsafe or surprising ways
- [x] Rework policy rendering so the zone surface cannot emit malformed nft rules
      for normal supported configurations
- [x] Narrow the module surface if necessary rather than claiming behavior that
      is not fully wired
- [x] Add targeted eval coverage or rendered-ruleset checks for the corrected
      composition model

## Verification

- [x] A representative `router-zones` configuration renders valid nftables syntax
- [x] Zone behavior composes with the base firewall model rather than replacing it
- [x] The docs clearly describe the resulting enforcement scope

## Notes

This reset narrows the first exported `router-zones` surface to a
**forward-only**, explicit zone-policy layer:

- no router-local per-zone input policy yet
- no raw nft rule passthrough
- unmatched traffic returns to the base `router-firewall` policy by default
