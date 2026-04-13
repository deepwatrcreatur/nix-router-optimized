# 05 Flake Checks Foundation

Status: `in-progress`

Suggested branch: `feat/router-flake-checks-foundation`

## Goal

Add an initial `checks` structure to `nix-router-optimized` so the flake has a
clear, CI-visible home for module smoke tests and evaluation guardrails.

## Why This Matters

Right now the repo exports modules and docs, but there is no obvious `checks`
output and no `tests/` tree. That makes it easy for regressions to slip through
until a downstream consumer imports the flake.

## Scope

- add a `checks` output to [`flake.nix`](../../flake.nix)
- create a lightweight layout for future tests, such as:
  - `tests/`
  - `checks/`
  - or a small helper under `lib/`
- keep the first version fast and evaluation-oriented
- document how new module tests should be added

## Suggested First Checks

- a flake-level “module import smoke” check for all exported modules
- at least one reusable helper to evaluate a minimal NixOS configuration that
  imports a router module
- one check that validates the default module bundle still evaluates

## Non-Goals

- a full VM test matrix in the first PR
- exhaustive runtime testing for every module

## Validation

- `nix flake check` shows at least one meaningful router-specific check
- future test PRs have a clear place to land without inventing structure again
