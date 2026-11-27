# Stability policy

Other flakes import these modules, so option names, types and defaults under
`services.router-*` (and the other options this flake declares) are a public
interface. This page says what changes between releases and how you will hear
about them.

## Versions

Releases are `0.x.y`. Until 1.0:

- A **patch** release (`0.x.y`) fixes bugs and adds options. It does not rename
  or remove options.
- A **minor** release (`0.x`) may rename, remove or change the default of an
  option. Every such change is listed under **Breaking** in
  [`CHANGELOG.md`](../CHANGELOG.md) and the release notes, with what to set
  instead.

`main` is what the maintainer's routers run. Pin a tag or a commit with
`flake.lock`, and read the changelog's Unreleased section before you update.

## How changes are made

- **Renames** keep the old name working for at least one minor release
  (`lib.mkRenamedOptionModule` or an equivalent warning), then remove it.
- **Removals** first turn the option into a warning that says what replaced it.
  `services.router-ha.keaSync` did this.
- **Default changes** that alter a running router's behaviour are listed under
  Breaking, even when the new default is the safer one.
- **Security fixes** may skip the deprecation period when the old behaviour was
  unsafe, for example a default secret in the Nix store. They then fail
  evaluation with a message that names the fix. A silent change is never used.
  An example is `vrrpPassword` (#153): a half-upgraded HA pair that silently
  lost authentication could elect two masters.

Evaluation checks (`tests/`) pin option behaviour. A change that breaks one
either updates the check and lists the change in the changelog, or is a bug.

## Not covered

- Options or backends described as experimental or preview, such as the Jool
  backends of `router-nat64` and `router-clat`, and the `router-clat` Elixir
  preview.
- Internal helpers under `modules/lib/`, script paths, environment variables
  passed to the dashboard API, and the API's JSON fields.
- The lab harness under `lab/`.
