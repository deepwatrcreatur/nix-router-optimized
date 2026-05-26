# 78 - Coarse CI Suites and Local Check Boundary

## Status: `ready`

## Objective

Reshape the exported `checks` surface in `nix-router-optimized` so CI exposes a
small number of deliberate top-level suites, while finer-grained checks remain
available for local debugging and targeted validation.

Suggested branch: `feat/router-coarse-ci-suites`

## Rationale

Round 132 maintained that `nix-router-optimized` should look more like the other
local flakes at the export boundary, but without abandoning Nix-first CI or
losing the underlying fine-grained checks.

The goal is therefore not:

- “delete validation”
- or “wrap everything in `linkFarm` and pretend the economics are solved”

The goal is:

- reduce the default exported CI surface to a few meaningful suites
- keep the canonical Nix validation logic in-repo
- preserve narrower checks for local/manual use
- and choose an aggregation shape that is honest about both failure semantics and
  repeated eval/setup work

## Requirements

- [ ] Reduce the default exported `checks` surface from the current
      many-leaf shape to a handful of top-level suites
- [ ] Keep the underlying fine-grained checks available somewhere repo-local for
      targeted developer use instead of deleting them outright
- [ ] Use an aggregation mechanism appropriate to the chosen suite semantics,
      such as:
      - a real suite derivation
      - `runCommand`-style aggregation
      - or another explicit Nix-native pattern
- [ ] Do not claim `linkFarm` alone is a billing fix unless the implementation
      actually removes repeated work rather than only hiding granularity
- [ ] Update any docs or contributor guidance that currently imply every leaf
      should stay directly exported in CI
- [ ] Preserve targeted validation entry points for the touched router areas

## Verification

- [ ] `nix flake show` / `nix eval` confirms the exported top-level check count is
      materially smaller than before
- [ ] The chosen suites still fail when an included leaf check fails
- [ ] A contributor can still run a narrower check path locally for debugging
- [ ] The repo docs explain the new CI-vs-local check boundary clearly

## Notes

This item is about **changing the exported flake boundary**, not about measuring
whether the new shape actually improved `nix-ci.com` costs.
