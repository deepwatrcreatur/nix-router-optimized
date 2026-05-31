# Router Nix CI Baseline

Last updated: 2026-05-31

## Objective

Record what the published `nix-router-optimized` mainline actually exposes to
GitHub/NixCI today, so maintainers do not confuse local or unpublished suite
experiments with the current public CI boundary.

## Scope And Evidence Limits

This record combines:

- the pre-change exported-surface audit in
  [`router-ci-check-surface-audit.md`](./router-ci-check-surface-audit.md)
- direct inspection of the published `github/main` flake and `tests/default.nix`
- provider-side GitHub/NixCI evidence for public main commit
  `f767a731984110699731a027377728cee12af4b1`

This record still does **not** include NixCI billing or worker-second totals.
It is about visible job shape, published repo state, and what conclusions are
safe from that evidence.

## Published Mainline Reality

As of GitHub `main` at `f767a731984110699731a027377728cee12af4b1`:

- `flake.nix` exports `checks`, but does **not** export `checksFineGrained`
- `tests/default.nix` directly assembles the narrow check set
- `tests/suites.nix` is not present on published `main`
- `tests/fine-grained.nix` is not present on published `main`

So the currently published mainline does **not** contain the coarse-suite split
described in items `78` and `79`.

## Provider-Side Evidence

Public evidence was gathered from the GitHub Checks API and linked `nix-ci.com`
run pages for main commit:

- `f767a731984110699731a027377728cee12af4b1`

Observed public check shape:

- total public check runs: `182`
- visible `build checks.x86_64-linux.*` runs: `178`
- visible `build packages.x86_64-linux.*` runs: `2`
- utility/provider jobs: `2`
  - `configure`
  - `show x86_64-linux`
- visible `ci-*` suite jobs: `0`
- visible `aarch64-linux` jobs: `0`

Representative public check names:

- `build checks.x86_64-linux.router-zones-sanitization-eval`
- `build checks.x86_64-linux.router-bgp-eval`
- `build checks.x86_64-linux.module-router-zones-import-eval`
- `build packages.x86_64-linux.router-diag`

Representative linked `nix-ci.com` run URL:

- `https://nix-ci.com/gh:deepwatrcreatur:nix-router-optimized/main/f767a731984110699731a027377728cee12af4b1/6616e1a5-f3ba-4681-8905-83ca7394e6fb`

Representative duration sample from the first visible page of `x86_64-linux`
leaf runs (`30` jobs sampled from the GitHub Checks API page-1 response):

- minimum observed duration: `2s`
- maximum observed duration: `31s`
- average observed duration: about `6.5s`

## Before / Current Summary

| Signal | Before planned suite split | Current published mainline | What is proven |
|---|---:|---:|---|
| Visible top-level `checks.x86_64-linux.*` jobs | `174` | `178` | Proven |
| Public `ci-*` suite jobs | n/a | `0` | Proven |
| Public package jobs | `2` | `2` | Proven |
| Public provider utility jobs | present | `configure`, `show x86_64-linux` | Proven |
| Direct worker-second/billing data | not captured | not captured | Not proven |

## Interpretation

The strongest supported conclusions today are:

- the current published public CI boundary is still narrow and fine-grained
- the coarse-suite shape discussed in earlier queue items is **not** the
  current public mainline reality
- any claim that the public provider now shows six suite jobs would be
  inaccurate for the published repo state measured on 2026-05-31

The still unproven conclusion is:

- exact `nix-ci.com` worker-second savings

So the most defensible label for the current result is:

- **provider evidence confirms that the published mainline still exposes the
  fine-grained public CI surface**

## Next-Step Recommendation

The next question is not “should the six suites be split more finely?”

The next question is:

- does the project want to actually land the coarse-suite implementation on
  published `main`, or explicitly keep the current fine-grained public surface?

Until that implementation question is resolved on the published branch, more
provider-side suite tuning is premature.
