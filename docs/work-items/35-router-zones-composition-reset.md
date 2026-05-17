# 35 - Router Zones Composition Reset

## Status: `in-progress`

## Objective

Reset `router-zones` to a composition model that is correct, explicit, and safe
with `router-firewall` before adding more feature surface to the module.

## Rationale

Discussion 06 concluded that the recent repo direction is mostly good, but that
`router-zones` is the one reviewed area where ordinary cleanup may no longer be
enough. The main concerns are:

- risky or invalid nft rendering around policy `extraRules`
- input-path behavior that may preempt or override base `router-firewall`
  semantics instead of composing with them
- a support boundary that is currently too easy for users to misunderstand

## Requirements

- [ ] Decide and document the composition contract between `router-zones` and
      `router-firewall`
- [ ] Ensure zone handling does not silently preempt base router-local policy in
      unsafe or surprising ways
- [ ] Rework policy rendering so the zone surface cannot emit malformed nft rules
      for normal supported configurations
- [ ] Narrow the module surface if necessary rather than claiming behavior that
      is not fully wired
- [ ] Add targeted eval coverage or rendered-ruleset checks for the corrected
      composition model

## Verification

- [ ] A representative `router-zones` configuration renders valid nftables syntax
- [ ] Zone behavior composes with the base firewall model rather than replacing it
- [ ] The docs clearly describe the resulting enforcement scope

## Notes

This item is intentionally phrased as a “reset” rather than a tiny bugfix.
Discussion 06 did not call for broad repo reimplementation, but it did judge
that `router-zones` is the strongest candidate for partial rework before further
feature growth.
