# 30 - Router Diag and Boundary Skills

## Status: `done`

## Objective

Create repo-local read-only skill artifacts around `router-diag` usage and the
architectural boundary between this flake and `unified-nix-configuration`.

## Rationale

Round 77 concluded that `router-diag` is a good skill candidate only when it is
explicitly constrained to safe, read-only use, and that contributors also need
an explicit reminder of what belongs in this repo versus what remains
source-of-truth in the consuming environment repo.

## Requirements

- [x] Add a repo-local `router-diag-operator-readonly` skill
- [x] Constrain the skill to safe read-only commands such as:
      - `show interfaces`
      - `show firewall`
      - `show vpn`
      - `show health`
- [x] Add a repo-local `integration-contract-with-unified-config` skill or
      equivalent explicit boundary artifact
- [x] Make clear that topology/source-of-truth interpretation may still belong
      in the consuming environment repo
- [x] Keep the skill free of any mutation, remediation, or "fix networking"
      behavior

## Verification

- [x] The repo contains explicit skill artifacts for read-only diagnostics and
      integration-boundary awareness
- [x] The diagnostics skill clearly states that it is observational only
- [x] The boundary skill clearly tells contributors what should stay in
      `nix-router-optimized` vs what belongs in `unified-nix-configuration`
- [x] No live router mutation path is introduced

## Notes

If the two artifacts feel too coupled for one PR-sized change, it is acceptable
for the read-only `router-diag` skill to land first and the boundary artifact to
follow shortly after.

## Outcome

- Added `.claude/skills/router-diag-operator-readonly/SKILL.md` with an explicit, read-only command set limited to `router-diag show interfaces`, `show firewall`, `show vpn`, and `show health`.
- Added `.claude/skills/integration-contract-with-unified-config/SKILL.md` to describe the boundary between reusable flake capabilities and consumer-owned topology or source-of-truth.
- Made stop conditions explicit so operators stop at observation or repo-boundary classification rather than drifting into live remediation.
