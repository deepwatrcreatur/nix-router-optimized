# Router Nix CI Baseline

Last updated: 2026-06-09

## Objective

Record what the published `nix-router-optimized` mainline actually exposes to
GitHub/NixCI today, and capture provider-side before/after evidence for the
coarse-suite transition so maintainers can tell whether the change was
cosmetic, economically real, or mixed.

## Evidence Sources

- GitHub Checks API for published `main` commits
- Local `nix flake show` evaluation of the current fine-grained and proposed
  coarse-suite check surfaces
- `nix-ci.com` run pages for public main commits

## Before: Published Fine-Grained Surface

As of GitHub `main` at `dd83c7d8888f6cc5dca4fdb1fe5d7e6227b31c07`:

- `flake.nix` exports `checks` with one derivation per narrow leaf test
- each leaf becomes an independent CI job on `nix-ci.com`

### Provider-Side Evidence (fine-grained)

| Signal | Value | Source |
|---|---:|---|
| Total public check runs | 182 | GitHub Checks API |
| `build checks.x86_64-linux.*` jobs | 178 | GitHub Checks API |
| `build packages.x86_64-linux.*` jobs | 2 | GitHub Checks API |
| Provider utility jobs | 2 | `configure`, `show x86_64-linux` |
| `aarch64-linux` jobs visible | 0 | GitHub Checks API |
| Per-job duration (min) | 0s | GitHub Checks API |
| Per-job duration (max) | 23s | GitHub Checks API |
| Per-job duration (avg) | ~6.2s | GitHub Checks API |
| Total worker-seconds (sum of all job durations) | ~1,101s | GitHub Checks API |
| Wall-clock span (first start to last completion) | ~299s | GitHub Checks API |

Representative check names:

- `build checks.x86_64-linux.router-nat64-eval`
- `build checks.x86_64-linux.module-router-zones-import-eval`
- `build checks.x86_64-linux.docs-router-clat-valid-minimal-eval`
- `build packages.x86_64-linux.router-diag`

### Failure-Debugging Ergonomics (fine-grained)

When a narrow leaf fails, the job name directly identifies the failing test:

```
build checks.x86_64-linux.router-nat64-jool-opt-in-required-fails  ❌
```

This immediately points to the exact module/assertion boundary without
expanding logs. For eval-only checks (the vast majority), this is a
meaningful debugging advantage.

## After: Coarse-Suite Surface

The proposed transition (implemented on `feat/router-translation-backend-surface`)
collapses all narrow leaves into 6 coarse CI suites per architecture:

| Suite | Contents |
|---|---|
| `ci-router-positive-evals` | NAT64, CLAT, BGP, SQM, mDNS, UPnP, Kea, HA, VPN, mwan, etc. |
| `ci-router-negative-boundaries` | Assertion/failure tests (Jool gates, HA blockers, zone guards) |
| `ci-docs-and-examples` | All doc-example eval checks |
| `ci-module-imports` | Per-module import smoke tests |
| `ci-dashboard-and-ui-contracts` | Dashboard inventory, firewall, service-control checks |
| `ci-runtime-unit-tests` | Runtime unit test derivations |

### Provider-Side Evidence (coarse, projected)

| Signal | Before (fine-grained) | After (coarse) | Change |
|---|---:|---:|---|
| Visible `checks.*` jobs | 178 | 6 | -97% |
| Total public CI jobs | 182 | ~10 | -95% |
| Per-job overhead (scheduling, container start) | 178 × overhead | 6 × overhead | -97% |
| Local narrow-leaf targeting | direct | via `nix build .#checksFineGrained.*` | preserved |

### Failure-Debugging Ergonomics (coarse)

When a coarse suite fails, the operator sees:

```
build checks.x86_64-linux.ci-router-positive-evals  ❌
```

This requires expanding the build log to find which individual leaf inside the
suite actually failed. The trade-off is a loss of one-glance debugging
specificity in exchange for dramatically fewer CI jobs.

Local debugging is unaffected because `checksFineGrained` still exposes every
narrow leaf.

## Interpretation

### What is proven

1. **Job count reduction is real**: 178 → 6 visible check jobs (97% reduction)
2. **Per-job scheduling overhead savings are structurally real**: each CI job
   carries fixed overhead (container scheduling, nix evaluation, result
   reporting). Reducing 178 jobs to 6 eliminates ~172 instances of that
   overhead.
3. **Average leaf duration is very short** (~6.2s per job). This means the
   fixed scheduling overhead is a significant fraction of total job cost.
4. **Local narrow-leaf debugging is preserved** via `checksFineGrained`.

### What is not proven

1. **Exact provider billing savings**: `nix-ci.com` billing model details are
   not available in the GitHub Checks API. Whether billing is per-job, per-
   second, or flat-rate determines the economic magnitude.
2. **Coarse-suite build time**: the 6 suites have not yet been measured on
   `nix-ci.com`. Local builds suggest each suite takes 30–90s (since they
   evaluate sequentially), but provider parallelism may differ.
3. **aarch64-linux behavior**: no aarch64 jobs appear today; the suite change
   has no measurable impact on a dimension that is already zero.

### Assessment

The suite transition is **mixed**:

- **Economically real** for scheduling overhead (structurally eliminates ~172
  scheduling round-trips per commit)
- **Likely real but unquantified** for billed cost (depends on provider billing
  model)
- **Cosmetically beneficial** for status UI (6 clear results vs. 178 noisy ones)
- **Minor debugging cost** for CI-only failures (need to expand logs to find the
  specific failing leaf)

## Recommendation

The current 6-suite shape is reasonable for the repo's scale:

- the suite categories are semantically meaningful (positive evals, negative
  boundaries, docs, imports, dashboard, runtime)
- no single suite is so large that a failure is undiagnosable
- local debugging retains full narrow-leaf granularity

**No further suite split is recommended** unless provider evidence shows that
one specific suite is disproportionately slow or that failures within a suite
are hard to localize in practice.

The repo should land the coarse-suite implementation on `main` and then
capture one real provider-side before/after measurement to close the billing
gap.
