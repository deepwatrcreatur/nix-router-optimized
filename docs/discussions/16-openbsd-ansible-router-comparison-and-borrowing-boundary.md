# Discussion 16: What Can `nix-router-optimized` Borrow from `francis-io/OpenBSD-Ansible-Router`?

**Status:** closed
**Opened:** 2026-06-08
**Participants requested:** GPT-4.1, GPT-5.4 mini, Claude Sonnet 4.6, and GitHub Copilot CLI

## Why this discussion exists

`nix-router-optimized` already has a much broader router ambition than
`francis-io/OpenBSD-Ansible-Router`.

- this repo has HA, richer dashboarding, VPN modules, IPv6/NAT64/DNS64/CLAT work,
  multi-WAN, BGP, and a larger design archive
- the OpenBSD repo is intentionally narrow:
  - OpenBSD
  - IPv4 only
  - `pf`
  - `dhcpd`
  - `unbound`
  - `sshd`
  - `ntpd`
  - a LAN-only static status page

That difference is exactly why the comparison is useful.

The question is not whether this repo should become more like the OpenBSD one in
scope or stack.

The real question is narrower:

- are there operational patterns in that repo that this one has not yet
  incorporated well enough?
- and if so, which ones are worth borrowing without regressing the broader NixOS
  design?

## Relevant current local context

From the current repo surface and recent local discussions:

- `README.md` already presents a much broader feature surface than the OpenBSD
  router intentionally supports
- `pkgs/router-diag/router-diag.sh` already provides a richer local status CLI
  than the OpenBSD repo's shell helper
- `router-dashboard` already exceeds the OpenBSD repo's static LAN page as the
  main operator UI
- recent HA work has made single-owner boundaries and promotion discipline more
  explicit, but the repo is still learning how to make risky live changes safer
- the repo has hardening docs and modules, but it does not yet have a clearly
  equivalent operator-facing security-validation runbook covering router-local,
  LAN-side, and WAN-side checks

## Source material reviewed

From `/tmp/OpenBSD-Ansible-Router`:

- `roles/pf/tasks/main.yml`
- `roles/network/tasks/main.yml`
- `roles/status_web/tasks/main.yml`
- `roles/base/tasks/main.yml`
- `roles/base/templates/router-status.j2`
- `roles/backup/tasks/main.yml`
- `roles/unbound/tasks/main.yml`
- `docs/router-security-validation.md`
- `group_vars/openbsd_routers/main.yml`
- `TODO.md`

## Participation record

What actually happened in this run:

- **GPT-4.1:** substantive
- **GPT-5.4 mini:** substantive
- **Claude Sonnet 4.6:** substantive
- **GitHub Copilot CLI:** substantive

This discussion is therefore recorded as a full four-seat run.

## Voice summaries

### GPT-4.1

- Strongest on the claim that the OpenBSD repo's value is mostly
  **operational discipline rather than feature parity**.
- Recommended borrowing:
  - staged firewall rollout with validation and last-known-good rollback
  - explicit interface confirmation gates
  - LAN-side health checks before persistence
  - protected backups before risky changes
  - and a security-validation runbook
- Strongest against copying the repo's narrow scope:
  `nix-router-optimized` should not give up its IPv6, HA, dashboard, or other
  richer capabilities just to imitate the OpenBSD router's simplicity.
- Bottom line:
  preserve the broader flake ambition, but import the safer live-change habits.

### GPT-5.4 mini

- Strongest on the **workflow** angle:
  the OpenBSD repo is useful because it makes risky operations more recoverable.
- Called out concrete borrowable ideas:
  - pre-change backup / rollback anchors
  - a three-view security-validation pattern
  - bootstrap / patching runbooks
  - a low-complexity local status fallback
  - and outbound-only monitoring patterns
- Also stressed that `nix-router-optimized` already exceeds the external repo in
  dashboarding, testing, HA, and feature scope, so the right move is not to
  clone the OpenBSD design literally.
- Bottom line:
  borrow the safety rails and operator workflow, not the OS-specific stack.

### Claude Sonnet 4.6

- Strongest on the **timed rollback with remote health-gate** pattern from the
  `pf` role.
- Highlighted the exact sequence:
  candidate render, syntax validation, last-known-good save, rollback timer,
  ephemeral apply, LAN-side health checks, and only then persistence.
- Drew the sharpest comparison with the current NixOS posture:
  generation rollback is valuable, but it is not the same thing as
  "do not let a risky firewall change become durable until remote reachability
  has been confirmed."
- Also identified two other strong local gaps:
  - no clearly equivalent three-viewpoint security-validation runbook
  - no explicit outbound bogon egress block comparable to the OpenBSD repo's
    WAN-side bogon rules
- Bottom line:
  the best transferable lesson is safer live-mutation discipline, not a change in
  architecture.

### GitHub Copilot CLI

- Strongest on the distinction between **what this repo already surpasses** and
  **what it still lacks operationally**.
- The OpenBSD repo's static status page and shell helper are not reasons to
  replace `router-dashboard` or `router-diag`.
- But its pre-apply validation discipline is still better in one important way:
  it tries to prove the live system still works from another vantage point before
  making a risky change durable.
- Also agreed that the OpenBSD repo's secrets-on-disk discipline
  (`KEY_FILE` / `TOKEN_FILE` style handling) maps well to a NixOS
  `LoadCredential` / runtime-file boundary where any modules still expose secrets
  too loosely.
- Bottom line:
  borrow the operational contract and secret-handling discipline, not the UI or
  the narrow platform surface.

## First-pass convergence

The voices converged strongly on the following points.

1. **`nix-router-optimized` already exceeds the OpenBSD router in feature
   breadth.**
   There is no case here for copying its IPv4-only scope, its lack of HA, its
   absence of dashboards, or its overall product boundary.

2. **The OpenBSD router is stronger on safe live mutation.**
   The clearest transferable lesson is not "use `pf`" or "be OpenBSD-like."
   It is:
   - validate before apply
   - keep a last-known-good anchor
   - test from another vantage point
   - and do not persist until health is proven

3. **This repo lacks a clearly equivalent security-validation runbook.**
   The OpenBSD repo's router-local / LAN-side / WAN-side validation framing is a
   better operator artifact than this repo currently exposes.

4. **Any borrowing should be NixOS-native.**
   The right imports are patterns, not mechanisms:
   - nftables rather than `pf`
   - systemd and generation-aware rollback rather than Ansible task rescue
   - repo-native docs and assertions rather than OpenBSD-specific shelling

5. **The best immediate follow-ups are mostly documentation and bounded safety
   improvements.**
   This comparison does not justify a module-architecture rewrite.

## Strongest ideas worth borrowing

### 1. A documented live-change safety pattern for firewall and routing mutations

This is the strongest borrow candidate.

The OpenBSD repo's `pf` workflow does something this repo does not yet present
as a first-class operator pattern:

- stage a candidate
- validate it
- preserve last-known-good
- apply with an automatic rollback path
- verify from outside the router itself
- and only then treat the new state as accepted

NixOS generations reduce some risk, but they do not fully replace this pattern.
They are closer to a recovery mechanism than to a live-change acceptance gate.

The practical local lesson is:

- at minimum, document the manual post-switch reachability checks and rollback
  path
- and later consider whether a bounded `router-firewall` health-gate or
  auto-rollback option is justified for physical-router deployments

### 2. A three-viewpoint router security validation runbook

The OpenBSD repo's `docs/router-security-validation.md` is one of the cleanest
things in the comparison set.

Its structure is portable:

- router-local checks
- LAN-side validation
- internet-side validation

This repo already has hardening features and docs, but not an equally explicit
"here is how you prove the running router still matches the intended security
posture" guide.

Because `nix-router-optimized` can intentionally expose more than the OpenBSD
router, this artifact is arguably even more important here.

### 3. Explicit outbound bogon egress blocking

The OpenBSD repo explicitly blocks WAN-side traffic to bogon / reserved
destinations.

This repo already has substantial hardening, but that specific defensive measure
is not yet surfaced clearly in the current local comparison.

This is attractive because it is:

- bounded
- low-risk
- and straightforward to test

### 4. Secret-handling discipline for agent-style services

The OpenBSD repo's outbound Beszel-agent setup reinforces a useful boundary:

- keep secrets in protected files
- do not expose them through casual process arguments
- and prefer runtime-file consumption patterns

This is not a major architectural revelation, but it is a good discipline worth
re-checking across monitoring and VPN-adjacent modules here.

### 5. A low-dependency fallback status surface

The OpenBSD repo's static LAN-only status page should not replace the current
dashboard.

But the comparison does suggest a narrower idea:

- a deliberately simple fallback status surface can still be valuable when the
  richer dashboard or supporting services are degraded

This is lower priority than the validation and rollback lessons, but it is the
best limited way to borrow from the OpenBSD repo's status approach without
regressing the main UI.

## Strongest reasons not to copy too much

1. **The OpenBSD router's simplicity depends on exclusions this repo does not
   want.**
   It is simpler partly because it intentionally does not do many of the things
   this repo exists to support.

2. **NixOS's declarative model is already a real advantage.**
   The repo should not import mutable-push habits or Ansible-shaped structure just
   because the external repo expresses safety carefully.

3. **The static status page is not a dashboard replacement.**
   `router-dashboard` and `router-diag` already exceed it as the primary operator
   surfaces.

4. **The OpenBSD repo's exact tooling is not portable.**
   `pfctl`, `rcctl`, `syspatch`, `doas`, OpenBSD `httpd`, and role-level Ansible
   logic are not themselves the valuable part of the design here.

5. **The repo's broader feature set remains a differentiator, not a mistake.**
   This comparison is useful because it sharpens safety and validation work, not
   because it reveals that the broader router project was aiming at the wrong
   problem.

## Maintained conclusion

`francis-io/OpenBSD-Ansible-Router` does not provide a better architectural model
for `nix-router-optimized`.

It does provide a better example of how to treat **risky live router mutation**
as a first-class operational problem.

The strongest maintained line from this discussion is:

- keep the broader NixOS router scope
- keep the richer dashboard and module surface
- but borrow the OpenBSD repo's discipline around:
  - rollback anchors
  - post-change validation
  - explicit security-verification runbooks
  - and tight secret-file boundaries

In other words:

**do not copy the OpenBSD router's product boundary; do copy its respect for the
fact that router changes can lock operators out of the network they are trying to
improve.**

## Recommended next steps

The best follow-up items, in order, are:

1. write a repo-local router security validation runbook
2. document a router firewall / routing apply-safety procedure with explicit
   rollback expectations
3. evaluate a bounded nftables bogon-egress hardening addition
4. audit monitoring and VPN-adjacent modules for credential-file discipline
5. only later consider a minimal fallback status surface if a real degraded-mode
   need remains

This discussion therefore closes with a **borrow-the-safety-rails, not the
architecture** recommendation.
