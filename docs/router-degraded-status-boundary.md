# Router Degraded-Mode Status Boundary

`nix-router-optimized` does **not** currently need a new static or fallback web
status surface beside `router-dashboard`.

The maintained boundary is:

- `router-dashboard` is the richer local HTTP status and control surface
- `router-diag` is the deliberately low-dependency read-only fallback
- troubleshooting and validation runbooks are the operator path when either
  richer surface is unhealthy

## Why The Current Surface Is Enough

### Existing degraded-mode coverage already spans the intended needs

- `router-diag` is packaged locally and limited to narrow read-only `show`
  commands:
  - `show interfaces`
  - `show firewall`
  - `show vpn`
  - `show health`
- `troubleshooting.md` already documents direct `systemctl`, `journalctl`, and
  local `curl` checks for dashboard and adjacent service failures.
- `router-security-validation.md` and `router-apply-safety.md` already define
  the post-change and rollback workflows that matter most when the richer
  dashboard path is degraded.

That combination already covers the meaningful degraded-mode cases better than a
second HTTP UI would.

### A second local status page would mostly duplicate the dashboard badly

The OpenBSD comparison that raised this question did **not** recommend replacing
`router-dashboard` or `router-diag` with a static page.

In this repo, a new fallback web surface would likely:

- duplicate partial dashboard data
- create another listener/binding decision to secure
- add another codepath that can drift from the real runtime checks
- and weaken the current clean distinction between rich HTTP UI and minimal CLI

That is too much attack surface and maintenance cost for too little new
operator value.

## Maintained Decision

The explicit repo answer is:

- **no new degraded-mode status surface for now**
- prefer better `router-diag` guidance and runbook clarity instead

This keeps the boundary simple:

- if the dashboard is healthy, use the dashboard
- if the dashboard or its dependencies are degraded, use `router-diag` and the
  troubleshooting/runbook docs
- if neither path gives enough evidence, inspect the underlying services
  directly rather than adding a second dashboard-like page

## What Counts As The Minimal Fallback Today

The approved low-dependency fallback is:

```sh
router-diag show interfaces
router-diag show firewall
router-diag show vpn
router-diag show health
```

If the packaged command is not installed in the environment yet:

```sh
nix run .#router-diag -- show interfaces
nix run .#router-diag -- show firewall
nix run .#router-diag -- show vpn
nix run .#router-diag -- show health
```

These commands are intentionally observational only. They are the degraded-mode
status boundary for this repo.

## Re-entry Gate For Any Future Fallback Surface

A new fallback surface should only be reconsidered if there is concrete evidence
that:

- `router-diag` cannot cover a recurring degraded-mode need
- the missing need is status visibility, not mutation or recovery
- and the new surface can stay narrower than the main dashboard on all of:
  - transport and binding
  - authentication expectations
  - content scope
  - and implementation dependencies

Absent that evidence, the better move is to improve `router-diag` output or the
operator runbooks rather than adding another HTTP status plane.
