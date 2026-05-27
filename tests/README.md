# Router Flake Checks

This directory contains fast evaluation-oriented checks for the flake. Add new
checks here when a module needs a minimal NixOS configuration, option assertion,
or other guardrail that should run in CI.

Prefer cheap checks that evaluate module configuration. Do not add VM tests here
until the repo intentionally grows a runtime test matrix.

## Export Boundary

The flake now exposes two check surfaces:

- `checks.<system>.*`: the small default CI suite surface
- `checksFineGrained.<system>.*`: the full narrow-leaf surface for local
  debugging and targeted validation

When adding a new check, put the canonical derivation in this directory first.
Then make sure it is included in the right exported suite rather than assuming
every new leaf should become a top-level CI job.

## Pattern

Use `mkNixosEvalCheck` from `nixos-eval.nix` for module smoke tests:

```nix
mkNixosEvalCheck "router-example" [
  self.nixosModules.router-example
  {
    services.router-example.enable = true;
  }
]
```

The helper evaluates `config.system.build.toplevel` and returns a small
derivation. This keeps checks CI-visible without forcing a full system closure
build.

## Local Targeting

Use the fine-grained output when you need one narrow check:

```bash
nix build .#checksFineGrained.x86_64-linux.router-example-eval
```

Use the default `checks` output when you want the coarse CI suites:

```bash
nix build .#checks.x86_64-linux.ci-router-positive-evals
```
