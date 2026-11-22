# Start Here

If you are a coding agent starting work in this repo, follow this file and it
should be enough to begin contributing.

## Objective

Pick the next highest-value work item that is not already in progress, do it in
its own branch, and keep the work scoped to one PR.

## Where The Work Queue Lives

Read first:

- [`README.md`](./README.md)
- [`agent-prompts.md`](./agent-prompts.md)

The authoritative work queue is the beads queue on the `beads-queue` branch,
used through `beads-q` (see [AGENTS.md](../../AGENTS.md#work-queue-beads)).
The markdown work items here are design and implementation specs.

## How To Choose Work

1. `beads-q ready --json` lists unblocked work; `beads-q show <id>` has the
   acceptance criteria and any linked work-item spec.
2. Claim with `beads-q update <id> --claim --actor <you>`. The claim is pushed
   at once, so agents on other machines see it. `CLAIM_CONFLICT` means someone
   else holds it: pick other work.
3. Before starting, check whether the suggested branch/worktree already exists.
   If it does but the bead is not claimed, treat it as stale and proceed
   carefully.
4. Don't mark progress in your branch; the bead's status is the claim. Close
   the bead after the PR merges, citing it.

## Worktree Guardrails

Treat the bare repo and the linked worktrees as different layers:

- the bare repo is the canonical Git object store
- `/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main` is the
  shared materialized checkout for reading, queue inspection, and branch
  creation
- feature work belongs in separate linked worktrees, not in the shared `main`
  checkout

Preserve these rules:

1. The shared `main` worktree must stay on branch `main`.
   Do not leave it parked on a feature/docs branch after opening a PR.
2. If you need to implement a work item, create or reuse a dedicated linked
   worktree for that branch.
3. If you discover the shared `main` worktree is not on branch `main`, stop and
   repair that before assuming the queue or branch names are wrong.
4. If a stale linked worktree exists, either:
   - reuse it deliberately if it clearly matches the intended branch
   - or prune/remove it before creating fresh work
5. Do not assume work-item numbers are stable forever; confirm by filename and
   title before concluding another agent is on “the same task.”

## Repo-Level Guardrails

Do not treat old queue examples as permanent repo-wide invariants.
This queue now spans routing, HA, firewall, DNS, DHCP, dashboard, and adjacent
router features.

Preserve these general guardrails unless the selected work item says otherwise:

- keep changes scoped to the selected work item rather than opportunistically
  broadening the product surface
- prefer explicit support boundaries over implied capability
- preserve existing single-active-owner / promotion-aware behavior where the
  task touches HA-sensitive services
- add or update docs when the user-facing support boundary changes

## PR Workflow

1. Validate locally as appropriate.
2. Push your branch and open a PR.
3. Wait briefly for CI and bot review.
4. Read comments and address substantive issues.
5. Merge only after checks are green or remaining comments are intentionally
   judged non-blocking.
