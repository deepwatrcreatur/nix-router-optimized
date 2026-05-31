# 80 - Nix CI Provider Evidence and Public Boundary Correction

## Status: `done`

## Objective

Capture real public-provider evidence for the post-item-`78` CI shape and
correct the docs if `nix-ci.com` is not actually exposing the six-suite boundary
that the local flake now exports.

Suggested branch: `docs/nix-ci-provider-evidence`

## Why This Existed

Item `79` intentionally stopped short of claiming provider-side savings without
real evidence. The remaining gap was:

- verify the public GitHub/NixCI run shape
- confirm whether the six-suite boundary is actually visible there
- correct the baseline if local export shape and provider-visible shape differ

## Requirements

- [x] Capture public-provider evidence for at least one current public commit
- [x] Record visible job count and representative job naming
- [x] Check whether any public `ci-*` suite jobs exist
- [x] Update the durable baseline with the provider-visible result
- [x] State whether further suite tuning is justified yet

## Verification

- [x] `docs/router-nix-ci-baseline.md` now includes provider-side evidence
- [x] The repo no longer claims without qualification that public CI is showing
      the six-suite surface
- [x] Future maintainers can distinguish local flake export shape from current
      public provider behavior

## Outcome

- Captured provider-side evidence on 2026-05-31 for public commit
  `f767a731984110699731a027377728cee12af4b1`.
- Observed `182` public check runs:
  - `178` narrow `build checks.x86_64-linux.*` jobs
  - `2` package builds
  - `2` utility jobs (`configure`, `show x86_64-linux`)
- Observed `0` public `ci-*` suite jobs.
- Updated [`docs/router-nix-ci-baseline.md`](../router-nix-ci-baseline.md) to
  record that the six-suite split is real locally but not currently reflected
  in the public NixCI surface.
- Concluded that the next useful step is provider-behavior diagnosis, not more
  repo-local suite splitting.
