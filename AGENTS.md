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
2. For helpers in `modules/lib/`, read the `/** */` doc comments (RFC 145)
   and keep them accurate. New exported helpers need one.
3. Read the module's doc (`docs/router-<name>.md`, or `docs/README.md` to find
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

<!-- nix-agent-guides:core BEGIN (v2). Synced from deepwatrcreatur/nix-agent-guides templates/agents-core.md by scripts/sync-agents-core.sh. Edit it there, not here. -->
## Shared conventions

Canonical, newest version:
https://raw.githubusercontent.com/deepwatrcreatur/nix-agent-guides/main/CONVENTIONS.md
If you can fetch it, read it before larger changes; where it differs from the
summary below, it is newer. This repo's own instructions above take
precedence over both.

Summary (offline fallback):

- **Comments explain why, not what.** Mark them `# WHY:`, `# GOTCHA:`,
  `# INVARIANT:`, `# SECURITY:`, `# UPSTREAM:` or `# TODO(#issue):`. One to
  three lines above the code they protect; longer reasoning goes in `docs/`
  with a pointer (`# WHY: docs/x.md#heading`). Never narrate the next line.
- **Before editing a file**, read its tags:
  `rg -n '# (WHY|GOTCHA|INVARIANT|SECURITY|UPSTREAM|TODO)' <file>`.
  Fix or delete any tag your change makes untrue.
- **Exported Nix functions** get RFC 145 doc comments (`/** ... */`).
- **Validate before committing:** the narrowest `nix build` first, then
  `nix flake check`; read all output. Run `bash -n`/`shellcheck` on shell
  generated from Nix. Exit code 0 is not proof the change worked.
- **Same change, same PR:** behaviour changes come with docs and a check.
- **Never commit secrets**, and do not deploy to or change live hosts unless
  asked.
<!-- nix-agent-guides:core END -->
