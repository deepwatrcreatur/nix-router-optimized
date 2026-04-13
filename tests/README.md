# Router Flake Checks

This directory contains fast evaluation-oriented checks for the flake. Add new
checks here when a module needs a minimal NixOS configuration, option assertion,
or other guardrail that should run in CI.

Prefer cheap checks that evaluate module configuration. Do not add VM tests here
until the repo intentionally grows a runtime test matrix.

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
