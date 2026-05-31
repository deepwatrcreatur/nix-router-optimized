# Router Nix CI Baseline

Last updated: 2026-05-31

## Objective

Record the before/after effect of the CI check-surface reshaping so future
maintainers can distinguish:

- proven visibility and ergonomics gains
- plausible but still unproven worker-second gains
- and any debugging tradeoffs introduced by the coarse suite boundary

## Scope And Evidence Limits

This record combines:

- the pre-change exported-surface baseline captured in
  [`router-ci-check-surface-audit.md`](./router-ci-check-surface-audit.md)
- the post-change flake state after item `78`
- local `nix eval` and `nix build` evidence gathered on 2026-05-26
- provider-side GitHub/NixCI evidence gathered on 2026-05-31 for public commit
  `f767a731984110699731a027377728cee12af4b1`

This record still does **not** include NixCI billing or internal worker-second
totals. It does now include public GitHub check-run evidence and the linked
`nix-ci.com` run URLs, which is enough to prove the current provider-visible job
shape and some per-job timing facts.

## Before / After Summary

| Signal | Before item `78` | Current public/provider state | What is proven |
|---|---:|---:|---|
| Exported top-level checks on `x86_64-linux` | `174` | `6` | Proven locally |
| Exported top-level checks on `aarch64-linux` | `174` | `6` | Proven locally |
| Fine-grained local leaf surface | `174` exported leaves | `178` visible `checks.x86_64-linux.*` jobs on the latest public run | Proven |
| Default CI-visible shape | one leaf per check | still fine-grained on the public provider | Proven |
| Public suite jobs named `ci-*` | n/a | `0` on the latest public run | Proven |
| Direct `nix-ci.com` worker-second data | not captured | not captured | Not proven |

The local exported-job reduction is still `174 -> 6`, which is a `96.6%` drop
in top-level check count. The public provider, however, is not currently
surfacing that six-suite boundary.

## Pre-Change Baseline

Source: [`router-ci-check-surface-audit.md`](./router-ci-check-surface-audit.md)

Before the suite reshaping:

- `checks.<system>.*` exposed `174` individual top-level jobs
- the exported surface mirrored the source tree almost one-to-one
- the surface included:
  - `44` generated module-import leaves
  - `21` doc/README example leaves
  - `73` explicit positive eval leaves outside generated imports
  - `32` explicit negative/failure leaves
  - `4` explicit runtime/unit-test leaves

Representative visible job shape before item `78`:

- `checks.x86_64-linux.module-router-kea-import-eval`
- `checks.x86_64-linux.router-dashboard-service-control-unit-tests`
- `checks.x86_64-linux.docs-router-wireguard-example-eval`

That shape maximized direct failure attribution, but it also maximized status
surface area and repeated the “one exported job per narrow leaf” pattern.

## Post-Change Local Baseline

After item `78`, the default exported flake `checks` surface is:

- `ci-module-imports`
- `ci-docs-and-examples`
- `ci-router-positive-evals`
- `ci-router-negative-boundaries`
- `ci-dashboard-and-ui-contracts`
- `ci-runtime-unit-tests`

The old leaf set remains available for targeted local work under:

- `checksFineGrained.<system>.*`

Confirmed local `nix eval` results on 2026-05-26:

- `checks.x86_64-linux` exports `6` leaves
- `checksFineGrained.x86_64-linux` exports `174` leaves

Representative local exported job shape after item `78`:

- one exported suite job such as `checks.x86_64-linux.ci-runtime-unit-tests`
- one local targeted debug leaf such as
  `checksFineGrained.x86_64-linux.router-nptv6-eval`

## Provider-Side Evidence

Public evidence was gathered on 2026-05-31 for GitHub commit:

- `f767a731984110699731a027377728cee12af4b1`
- commit URL:
  `https://github.com/deepwatrcreatur/nix-router-optimized/commit/f767a731984110699731a027377728cee12af4b1`

Observed through the GitHub Checks API for that commit:

- total public check runs: `182`
- visible `build checks.x86_64-linux.*` runs: `178`
- visible `build packages.x86_64-linux.*` runs: `2`
- non-build utility runs: `2`
  - `configure`
  - `show x86_64-linux`
- visible `ci-*` suite jobs: `0`
- visible `aarch64-linux` jobs: `0`

Representative public check names:

- `build checks.x86_64-linux.router-zones-sanitization-eval`
- `build checks.x86_64-linux.router-bgp-eval`
- `build checks.x86_64-linux.module-router-zones-import-eval`
- `build packages.x86_64-linux.router-diag`

Representative linked `nix-ci.com` run URL from the GitHub Checks API:

- `https://nix-ci.com/gh:deepwatrcreatur:nix-router-optimized/main/f767a731984110699731a027377728cee12af4b1/6616e1a5-f3ba-4681-8905-83ca7394e6fb`

Representative duration sample from the first visible page of `x86_64-linux`
leaf runs (`30` jobs sampled from the GitHub Checks API page-1 response):

- minimum observed duration: `2s`
- maximum observed duration: `31s`
- average observed duration: about `6.5s`

Interpretation:

- the current public NixCI/GitHub surface is still narrow-leaf and
  implementation-detailed
- the six-suite split is real in the flake exports, but it is **not** the
  current public CI boundary
- the earlier claim that operators now see six suite jobs by default is no
  longer accurate for the public provider evidence gathered on 2026-05-31

## Local Build Evidence

The following post-change local builds were executed on 2026-05-26:

- `nix build --impure .#checks.x86_64-linux.ci-runtime-unit-tests`
  - completed in `2.562s`
  - build output showed `5` derivations:
    - `4` underlying unit-test leaves
    - `1` suite wrapper derivation
- `nix build --impure .#checksFineGrained.x86_64-linux.router-nptv6-eval`
  - completed in `4.424s`

What this proves:

- the coarse exported suite path works end-to-end locally
- the preserved fine-grained local path works end-to-end
- at least one exported suite now aggregates several previously separate leaves
  into a single visible top-level job
- the public provider is currently not exposing those suites as the visible job
  surface

What this does **not** prove:

- that all suite builds are faster than all former leaf builds
- that `nix-ci.com` billed worker-seconds definitely fell at all
- that repeated eval/build/setup cost was eliminated across every family

## Representative CI Shape Comparison

### Before

Operators and CI UIs saw one visible job per narrow leaf.

Examples:

- one job for a doc example
- one job for a single module-import check
- one job for one runtime unit-test leaf

This made failures immediately attributable, but produced a very wide CI/status
surface.

### Local flake after item `78`

The flake export now has a small suite list by default, while developers can
still drop to a narrow leaf locally through `checksFineGrained`.

Example:

- `ci-runtime-unit-tests` is one exported job
- it wraps the four runtime/unit-test leaves behind that suite

This would clearly reduce UI and status clutter if the provider exposed the same
surface.

### Current public provider state

The latest observed public run still shows one visible job per narrow leaf plus
package builds.

So, for public GitHub/NixCI users, the practical shape is still much closer to
the **before** state than to the intended six-suite state.

## Failure Attribution And Debugging Ergonomics

### Improvement

- local contributor ergonomics improved because the flake now has a clear
  default suite surface and a separate narrow debug surface
- the exported flake shape now communicates intentional families instead of an
  implementation-detail leaf list

### Regression Risk

- because the public provider still shows narrow leaves, maintainers now have a
  doc/reality mismatch instead of the expected coarse-suite tradeoff
- future maintainers may incorrectly assume NixCI cost or noise improved when
  the public run shape shows that it did not

### Mitigation

- the exact old leaf surface still exists under `checksFineGrained`
- contributor docs now point targeted debugging at
  `nix build .#checksFineGrained.<system>.<leaf>`
- this baseline now records the provider mismatch explicitly

Current judgment:

- debugging did not regress too far, because the narrow leaf surface was
  preserved rather than deleted
- public CI ergonomics did **not** receive the documented six-suite win, because
  the provider is still exposing the narrow leaves

## Economic Interpretation

The strongest supported conclusions today are:

- the flake itself really was reshaped to a six-suite default `checks` surface
- the public provider is still showing narrow `checks.x86_64-linux.*` leaves
  rather than those six suites

The weaker, still only partially evidenced conclusions are:

- some local suite builds may reduce per-job overhead
- the suite split may still be useful for local contributor workflow

The still unproven conclusion is:

- exact `nix-ci.com` worker-second savings

So the most defensible label for the current result is:

- **mixed, with a real local export-boundary cleanup but no demonstrated public
  NixCI surface reduction**

## Next-Step Recommendation

The next question is no longer “should the six suites be split more finely?”
The next question is:

- why is the public provider still exposing `178` narrow `checks.x86_64-linux`
  leaves when the flake exports only six top-level `checks` attrs locally?

The first follow-up points to check are:

- whether the provider is evaluating a different output boundary than
  `checks.<system>`
- whether the public provider is expanding suite contents into separate visible
  check runs by design
- whether the provider is reading a stale or alternative ref/configuration path

Until that is understood, there is no evidence that further suite tuning inside
the repo would change the public `nix-ci.com` surface.
