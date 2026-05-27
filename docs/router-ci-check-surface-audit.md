# Router CI Check Surface Audit

Last updated: 2026-05-26

## Objective

Map the current exported `checks` surface in `nix-router-optimized`, separate
default CI visibility from local debugging granularity, and define a concrete
suite plan for follow-up work.

## Current Export Boundary

`flake.nix` exports:

- `checks = forAllSystems (system: import ./tests { ... })`

That means the entire attrset returned by [`tests/default.nix`](../tests/default.nix)
is CI-visible today on both `x86_64-linux` and `aarch64-linux`.

Live count on 2026-05-26:

- `174` exported leaves under `checks.x86_64-linux.*`
- `174` exported leaves under `checks.aarch64-linux.*`

## How The 174 Leaves Are Produced

The current surface is assembled from a few distinct construction patterns:

| Source | Exported leaves | Construction style | Notes |
|---|---:|---|---|
| Generated module import coverage in `tests/default.nix` | `44` | `lib.mapAttrs'` + `mkNixosEvalCheck` | One leaf per exported `self.nixosModules.*`, including `default` |
| Doc/README examples in `tests/doc-examples.nix` | `21` | `mkDocExampleCheck` using `pkgs.runCommand` | Positive example coverage, but each leaf evaluates a full `nixosSystem` |
| Explicit positive eval leaves outside generated imports | `73` | `mkNixosEvalCheck` | Router feature checks, dashboard contracts, invariants |
| Explicit negative/failure leaves | `32` | `mkNixosEvalFailureCheck` | Assertion and boundary checks |
| Explicit runtime/unit-test leaves | `4` | direct `pkgs.runCommand` | Python/Elixir dashboard and CLAT unit tests |

Total: `44 + 21 + 73 + 32 + 4 = 174`

## Breakdown By Test File

This is the practical family map a contributor currently has to infer from
`tests/default.nix`:

| File | Leaves | Main role |
|---|---:|---|
| `tests/default.nix` | `46` | repo-surface guardrails plus generated module import coverage |
| `tests/doc-examples.nix` | `28` | README/docs example evaluation, CLAT doc failures, CLAT unit tests |
| `tests/vpn-smoke.nix` | `27` | overlay VPN, tunnel, remote-admin, and metadata coverage |
| `tests/pro-features-smoke.nix` | `19` | NAT64, DNS64, SQM, mDNS, UPnP, BGP, Technitium, HA DNS |
| `tests/router-dashboard-inventory.nix` | `7` | dashboard inventory contracts and runtime unit tests |
| `tests/router-zones.nix` | `9` | zone policy positive and negative boundaries |
| `tests/router-kea-eval.nix` | `8` | Kea and DHCP option 108 coverage |
| `tests/interface-firewall-invariants.nix` | `6` | interface derivation and VPN/firewall invariants |
| `tests/router-dashboard-service-control.nix` | `5` | dashboard mutation/auth boundary and unit tests |
| `tests/router-security-hardened.nix` | `6` | security hardening assertions |
| `tests/router-mwan-eval.nix` | `4` | IPv6 multi-WAN guardrails |
| `tests/router-clat-observability.nix` | `2` | CLAT metadata and rendered config |
| `tests/router-dhcp-option108-boundary.nix` | `2` | unsupported backend boundary |
| `tests/router-dashboard-firewall.nix` | `1` | dashboard firewall browser contract |
| `tests/router-ha-boundaries.nix` | `1` | HA NTP boundary docs coverage |
| `tests/router-nptv6.nix` | `1` | NPTv6 smoke |
| `tests/router-pvd.nix` | `1` | PvD smoke |

The current export boundary therefore mirrors the source tree almost one-to-one
instead of presenting a deliberate CI surface.

## What Should Stay CI-Visible

These families still belong in default CI on every change:

- module import coverage for every exported `nixosModule`
- a bounded set of repo-surface guardrails such as default bundle/export checks
- docs/README examples that represent published adoption paths
- negative boundary checks for assertions and explicit non-support
- dashboard/browser/API contract coverage
- router feature eval coverage for core supported features
- small repo-local unit tests that validate generated dashboard/CLAT runtime data

The issue is not that these checks exist. The issue is that every leaf is
exported individually.

## What Should Move Behind Coarser Suites

The following should stop being directly exported as top-level `checks.*`
leaves:

- all `module-*-import-eval` leaves
- all individual doc/README example leaves
- all individual router feature eval leaves
- all individual negative/failure leaves
- all individual dashboard/browser contract leaves
- all direct runtime/unit-test leaves
- repo-surface guardrail leaves such as `default-module-bundle-eval` and
  `exported-module-list-eval`

These leaves should remain available for local debugging and targeted manual
validation, but not as the default public CI surface.

## Proposed Exported CI Shape

Target exported shape for item `78`: `6` top-level suites.

1. `ci-module-imports`
   - Includes all generated `module-*-import-eval` leaves.
   - Keeps the guarantee that every exported module still imports cleanly.

2. `ci-docs-and-examples`
   - Includes README/doc example leaves from `tests/doc-examples.nix`.
   - Includes doc-sourced CLAT boundary checks because they protect published
     operator guidance.

3. `ci-router-positive-evals`
   - Includes positive feature evals across firewall, zones, Kea, BGP, NAT64,
     DNS64, NPTv6, PvD, HA DNS, security hardening, and overlay/tunnel modules.
   - This is the main “supported feature still evaluates” suite.

4. `ci-router-negative-boundaries`
   - Includes `mkNixosEvalFailureCheck` leaves across zones, Kea, dashboard
     service control, dashboard inventory, DHCP option 108 boundaries, MWAN,
     BGP, security hardening, and overlay collision checks.
   - Keeps explicit unsupported or assertion-driven boundaries visible.

5. `ci-dashboard-and-ui-contracts`
   - Includes dashboard inventory/service-control/firewall/browser contract
     leaves and metadata surfaces that primarily protect UI/API expectations.
   - Keeps dashboard regressions attributable without exposing every single
     widget-related leaf separately.

6. `ci-runtime-unit-tests`
   - Includes the explicit `runCommand` unit tests:
     - dashboard inventory runtime tests
     - dashboard service-control unit tests
     - CLAT DNS unit tests
     - CLAT Elixir unit tests
   - Keeps non-eval runtime-ish validation separate from pure NixOS eval suites.

This shape is small enough to be intentional in CI, but still specific enough
to preserve failure meaning.

## Direct Export Recommendation

Default CI should export suites, not fine-grained leaves.

Recommended direct exports after item `78`:

- only the suite derivations listed above

Recommended non-default local/debug surface:

- keep the current fine-grained attrsets in `tests/`
- expose them through a non-default flake output such as
  `checksFineGrained.<system>.*`
- preserve the ability to run a narrow check path without reintroducing
  `174` top-level CI jobs

## Why Six Suites Instead Of Three

Collapsing everything into `3` giant suites would make CI quieter, but it would
hide too much debugging signal:

- runtime/unit-test failures should not be mixed with pure eval families
- dashboard contract regressions are operationally different from router module
  assertion failures
- negative boundary coverage should remain distinguishable from positive feature
  coverage

Six suites keeps the surface deliberate without making every failure start from
scratch.

## Obvious Repeated Work To Factor

The current surface repeats full NixOS evaluation many times:

- every `mkNixosEvalCheck` leaf constructs a `nixosSystem` and forces
  `config.system.build.toplevel`
- every `mkNixosEvalFailureCheck` leaf constructs a `nixosSystem` inside
  `tryEval`
- every `mkDocExampleCheck` leaf separately builds its own example evaluation
- the generated module-import fan-out creates `44` separate top-level leaves for
  simple import safety

Important consequence:

- replacing many leaves with `linkFarm` alone would reduce UI clutter, but would
  not by itself prove worker-second savings

If item `78` wants real cost improvement, not just a cleaner UI, it should
favor suite derivations that actually aggregate repeated work rather than merely
renaming the same amount of evaluation.

## Implementation Guidance For Item 78

Item `78` should:

- keep the canonical fine-grained family attrsets in `tests/`
- build explicit suite derivations from those family attrsets
- export only the suite derivations from `flake.nix`/`tests/default.nix`
- expose the legacy narrow-leaf surface through `checksFineGrained`
- document how contributors still run narrow leaves locally
- avoid claiming economic wins until item `79` captures before/after evidence

## Local-Only Surface Recommendation

After the export boundary changes, contributor guidance should point narrow
debugging flows at:

- the relevant `tests/*.nix` family file
- the fine-grained attrset name used to build a suite
- a documented local invocation path such as
  `nix build .#checksFineGrained.x86_64-linux.<leaf>`

That preserves the current debugging ergonomics without keeping every leaf
publicly exported in CI.
