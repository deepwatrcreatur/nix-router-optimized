# Router Nix CI Baseline

Last updated: 2026-05-26

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

This environment did **not** include direct `nix-ci.com` UI or billing access.
That means the record can prove the exported-job reduction and some local build
shape facts, but it cannot by itself prove exact worker-second savings on the
CI provider.

## Before / After Summary

| Signal | Before item `78` | After item `78` | What is proven |
|---|---:|---:|---|
| Exported top-level checks on `x86_64-linux` | `174` | `6` | Proven |
| Exported top-level checks on `aarch64-linux` | `174` | `6` | Proven |
| Fine-grained local leaf surface | `174` exported leaves | `174` leaves under `checksFineGrained` | Proven |
| Default CI-visible shape | one leaf per check | six suites | Proven |
| Direct `nix-ci.com` worker-second data | not captured | not captured | Not proven |

The visible exported-job reduction is `174 -> 6`, which is a `96.6%` drop in
top-level check count.

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

## Post-Change Baseline

After item `78`, the default exported CI surface is:

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

Representative visible job shape after item `78`:

- one CI-visible suite job such as `checks.x86_64-linux.ci-runtime-unit-tests`
- one local targeted debug leaf such as
  `checksFineGrained.x86_64-linux.router-nptv6-eval`

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

- the coarse exported suite path works end-to-end
- the preserved fine-grained local path works end-to-end
- at least one exported suite now aggregates several previously separate leaves
  into a single visible top-level job

What this does **not** prove:

- that all suite builds are faster than all former leaf builds
- that `nix-ci.com` billed worker-seconds definitely fell by the same ratio as
  the visible job count
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

### After

Operators and CI UIs see a small suite list by default, while developers can
still drop to a narrow leaf locally through `checksFineGrained`.

Example:

- `ci-runtime-unit-tests` is one exported job
- it wraps the four runtime/unit-test leaves behind that suite

This clearly reduces UI and status clutter. It also shifts some initial failure
triage from “already narrow” to “identify the failing leaf inside the suite,”
which is the main debugging tradeoff of the new shape.

## Failure Attribution And Debugging Ergonomics

### Improvement

- CI dashboards are materially less noisy
- the exported surface now communicates intentional families instead of an
  implementation-detail leaf list

### Regression Risk

- a failing suite is coarser than a failing leaf
- default CI no longer tells the operator the exact narrow check name before
  drilling in

### Mitigation

- the exact old leaf surface still exists under `checksFineGrained`
- contributor docs now point targeted debugging at
  `nix build .#checksFineGrained.<system>.<leaf>`

Current judgment:

- debugging did not regress too far, because the narrow leaf surface was
  preserved rather than deleted

## Economic Interpretation

The strongest supported conclusion today is:

- the main proven gain is reduced UI/status clutter and a clearer exported CI
  boundary

The weaker, only partially evidenced conclusion is:

- some suites may reduce per-job overhead by aggregating multiple narrow leaves
  behind one visible exported job

The still unproven conclusion is:

- exact `nix-ci.com` worker-second savings

So the most defensible label for the current result is:

- **mixed, with a clearly real cosmetic/ergonomic win and a plausible but not
  yet provider-measured economic win**

## Next-Step Recommendation

If maintainers want to prove the economic effect more rigorously, capture from
`nix-ci.com` for a comparable pre/post commit pair:

- visible job count
- total worker-seconds
- wall-clock duration
- cache-hit behavior
- and failure-debugging screenshots or notes for one representative failed run

If future operators find the suite boundary too coarse, the first place to
split more finely is likely:

- `ci-router-positive-evals`
- or `ci-module-imports`

There is no current evidence that the six-suite split is too coarse to keep.
