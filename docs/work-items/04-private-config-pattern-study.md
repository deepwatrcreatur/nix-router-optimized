# 04 Private Config Pattern Study

Status: `in-progress`

Suggested branch: `docs/router-private-config-pattern-study`

## Goal

Study the private-configuration pattern used in
`joshpearce/nix-router` and determine which parts should be borrowed into
`nix-router-optimized` without turning this flake into a single-user appliance
repo.

## Scope

- review the committed `private.example/`, `private/`, and `private-options.nix`
  approach used in `joshpearce/nix-router`
- identify which ideas are worth borrowing:
  - example private config templates
  - typed option schemas
  - bootstrap and secret-management docs
- explicitly reject anything that would make this flake less reusable for
  downstream consumers

## Validation

- leave behind a short recommendation of:
  - borrow now
  - defer
  - reject
- keep the recommendation grounded in `nix-router-optimized` being a reusable
  flake, not a one-off router repo

## Outcome

- Recommendation: [`../private-config-pattern-study.md`](../private-config-pattern-study.md)
