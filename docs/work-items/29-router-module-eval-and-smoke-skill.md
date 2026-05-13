# 29 — Router Module Eval and Smoke Skill

## Status: `done`

## Objective

Create a repo-local skill for `nix-router-optimized` that tells agents how to
choose and run the right eval/smoke checks for the part of the router flake
they are changing.

## Rationale

Round 77 concluded that this repo's strongest skill candidate is not "run `nix
flake check`" but a concrete procedure that maps module changes to the relevant
checks under `tests/` and exported flake checks. That knowledge is real,
reusable, and specific to this flake's module surface.

## Requirements

- [x] Add a repo-local skill artifact for `router-module-eval-and-smoke-loop`
- [x] Encode a practical mapping from touched areas to likely checks, such as:
      - exported module/import evals
      - doc/examples eval coverage
      - interface/firewall invariants
      - VPN smoke tests
      - Kea eval checks
      - NPTv6 / PvD checks
- [x] Make the skill explicitly read-only and validation-focused
- [x] Keep live deployment/rebuild behavior out of scope
- [x] Update nearby onboarding/docs only if needed to make the skill discoverable

## Verification

- [x] The repo contains an explicit skill artifact for this loop
- [x] A contributor can follow it to select a narrower check set for at least
      two different module change types
- [x] The skill clearly distinguishes targeted validation from "run everything"
- [x] The skill does not imply or grant live router mutation

## Notes

This should become the router-flake equivalent of a test-selection discipline,
not a vague "do validation" prompt.


## Outcome

- Added `.claude/skills/router-module-eval-and-smoke-loop/SKILL.md` with an explicit, read-only procedure for choosing targeted eval and smoke checks by touched router area.
- Documented concrete mappings for exported module evals, doc/example coverage, interface and firewall invariants, VPN smoke checks, Kea evals, and NPTv6 / PvD validation.
- Kept the scope validation-only and explicitly excluded live deployment or rebuild workflows.
