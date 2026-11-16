# Notes for coding agents and contributors

`nix-router-optimized` is a flake of NixOS modules for building a router
(`modules/`), with eval checks in `tests/` and docs in `docs/`. Other flakes
consume it, so option names and defaults are a public interface.

## Before changing a module

1. Read the tagged comments in the file. They record why code looks the way it
   does and what breaks if it is "simplified":

   ```sh
   rg -n '# (WHY|GOTCHA|INVARIANT|SECURITY|UPSTREAM|TODO)' modules/<file>.nix
   ```

   The tag meanings are in `docs/module-authoring.md#code-comment-tags`. Add
   tags for new non-obvious decisions, and fix or remove tags that your change
   makes untrue.
2. Read the module's doc (`docs/router-<name>.md`, or `docs/README.md` to find
   it) and the "Lessons From Production" section of `docs/module-authoring.md`.

## Validating

- Run the narrowest checks first: `nix build .#checks.x86_64-linux.<name>`.
  Checks live in `tests/*.nix`. The `router-module-eval-and-smoke-loop` skill
  in `.claude/skills/` explains how to pick them.
- Shell embedded in Nix: build the unit and run `bash -n` / `shellcheck` on the
  generated script.
- Do not deploy to, rebuild, or change live routers from this repo.

## Recurring pitfalls

- Technitium's API returns HTTP 200 for errors. Check `.status == "ok"`.
- Upstream NixOS modules may default things you need to `null` (Suricata
  `outputs`). Set what you depend on explicitly.
- Upstream units are sandboxed (`ProtectSystem=strict`, `DynamicUser`). New
  paths need `ReadWritePaths`/`ReadOnlyPaths`.
- Sync units that create external objects must also remove the ones they own
  when they leave the config.

## Commits and PRs

- Keep option changes backwards compatible, or document the migration in the PR
  and docs.
- Update docs and add or extend an eval check in the same PR as the behaviour
  change.
