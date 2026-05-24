# Discussion 14: Whether Router VMs Should Lock Kernel Module Loading

**Status:** closed
**Opened:** 2026-05-24
**Participants requested:** Codex CLI, GitHub Copilot CLI, Gemini CLI, DeepSeek API, and one OpenCode free-model seat

## Why this follow-up exists

The router repo already has a visible hardening story, but it also now has a
more explicit HA and recovery story.

- `docs/router-security-hardened.md` already claims a meaningful hardening
  surface
- the repo increasingly tries to be honest about failover and recovery rather
  than overclaiming maturity
- and the current real consumer posture is still VM-centric, with `router` as
  the active owner and `router-backup` as a management-first standby by default

That raises a concrete hardening question:

- should the repo add or recommend `security.lockKernelModules = true;` for
  router VMs?

This is not just generic Linux advice.
It depends on whether the repo can honestly support that choice across the
current router feature set and HA posture.

## Relevant prior context

From `docs/router-security-hardened.md`:

- the project already values kernel hardening and blacklisting dangerous or
  irrelevant modules
- but it does not currently claim a fully locked-down immutable-kernel posture

From `docs/router-ha-ownership.md`:

- the supported near-term posture is still single active owner
- and the standby is intentionally kept conservative while promotion boundaries
  are sharpened

From the current repo/code surface:

- there are no current references to `security.lockKernelModules`
- the repo includes or references features like:
  - nftables / flowtable acceleration
  - Tailscale
  - WireGuard
  - Tayga / NAT64
  - miniupnpd
  - Keepalived / VRRP
  - an experimental declarative CLAT first slice

That means the question is not whether module locking is ever good.
It is whether this repo, with this runtime surface and this current recovery
model, should support or recommend it now.

## Question for this discussion

Should `nix-router-optimized` add or recommend
`security.lockKernelModules = true;` for router VMs now?

More concretely:

1. What is the strongest argument for adding or recommending it?
2. What is the strongest argument against doing that now?
3. Is this best treated as:
   - a repo-supported option
   - a consumer-side hardening choice
   - or something the repo should avoid for now?
4. Which repo features or operational paths are most likely to conflict with
   module locking?
5. Should the answer differ between the active router VM and the current
   management-first standby posture?
6. What judgment should be recorded in the local discussion archive?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **GitHub Copilot CLI:** substantive
- **Gemini CLI:** substantive
  - emitted a keychain warning and fell back to file-backed credential storage
  - still returned a usable answer body
- **DeepSeek API:** substantive
  - run through the real DeepSeek HTTPS API using the local decrypted key and an
    explicit CA bundle
- **OpenCode free-model seat:** non-substantive
  - returned only a one-line verdict stub via `opencode/nemotron-3-super-free`
  - not rich enough to count as a full voice summary

This round is therefore recorded as a **mostly full real roster**:

- four substantive seats
- plus one verdict-only free-model seat

The only degraded part of the run is that the OpenCode seat returned only a
bottom-line verdict rather than a developed argument.

## Voice summaries

### Codex CLI

- Strongest on the **support-boundary honesty** argument:
  upstream should not recommend module locking until it can prove explicit
  preload coverage for concrete router profiles.
- Most specific about likely repo conflict surfaces:
  - PPPoE
  - WireGuard
  - Tailscale
  - Tayga / CLAT / `tun`
  - flowtable/offload paths
  - Keepalived promotion-time service starts
  - and VM recovery paths where late driver/module availability still matters
- Drew the sharpest deployment boundary:
  if anyone experiments with this now, it should happen first in consumer space
  on fixed Proxmox-style lab VMs, with cold-boot, service-restart, and
  promotion-drill validation rather than by upstream recommendation.
- Bottom line was strongly conservative:
  advanced consumer-side experiment only, not a repo-supported default.

### GitHub Copilot CLI

- Strongest on the **timing** issue:
  NixOS locks module loading early enough that any router feature relying on
  later autoload becomes a real operational risk.
- Most explicit that the current repo does not own a typed guarantee for
  “everything needed was already loaded before the lock point.”
- Called out conflict candidates across both dataplane and recovery surfaces:
  - PPPoE
  - Tailscale / WireGuard / OpenVPN
  - Tayga / CLAT
  - nftables flowtable and conntrack/offload dependencies
  - VM drivers and guest recovery/debugging assumptions
- Took a slightly different first-experiment angle than Codex:
  if a consumer insists on trying this, the management-first standby is the
  safer test surface initially, but that still does not justify upstream support
  or recommendation.

### Gemini CLI

- Strongest on the **operational fragility** argument:
  module locking is attractive in principle, but brittle in a repo whose
  networking features may still rely on on-demand module loading.
- Most explicit that the repo currently lacks:
  - a pre-audited required-module set
  - a typed support boundary
  - and confidence that all needed modules are loaded before lock-down
- Treated likely conflict surfaces as:
  - Tayga / `tun`
  - flowtable offload
  - Tailscale / WireGuard
  - and Proxmox-style recovery paths where late flexibility still matters
- Preferred an eventual **advanced opt-in** only after feature-by-feature module
  auditing rather than a broad recommendation now.
- Most skeptical of locking the standby:
  the management/recovery node should preserve flexibility unless the project has
  much stronger promotion and recovery guarantees than it has today.

### DeepSeek API

- Strongest on the **defense-in-depth** case:
  preventing runtime module loading does materially reduce the post-compromise
  attack surface on a security-critical edge host.
- Still converged on the same practical blocker:
  the repo cannot currently prove that all required modules are present before
  the lock point for its supported router feature combinations.
- Most explicit on the support-boundary framing:
  this is best treated as a **consumer-side hardening choice with repo-side
  documentation**, not as a default posture the flake should broadly recommend.
- Called out likely conflict and recovery surfaces including:
  - Proxmox guest recovery assumptions
  - WireGuard / Tailscale
  - Tayga / NAT64
  - miniupnpd helper paths
  - Keepalived-related role changes
  - and the experimental CLAT path
- Treated the active-vs-standby split differently from Gemini:
  it viewed the standby as somewhat safer to lock because it runs less, but still
  not something the repo should recommend without stronger support boundaries.

### OpenCode free-model seat (`opencode/nemotron-3-super-free`)

- Returned only a verdict-level line:
  do not add or recommend this now; leave it as a consumer-side hardening choice
  until required modules and recovery implications are verified.

Because the seat did not return substantive reasoning beyond that bottom line, it
is recorded as supporting evidence rather than a full peer voice.

## First-pass convergence

The substantive voices converged strongly on the following points.

1. **Module locking is security-positive in principle, but the repo is not ready
   to recommend it as a normal router posture.**
   Both substantive voices agreed that the best case is clear:
   it reduces the ability of an attacker to load new kernel attack surface or
   persistence mechanisms after gaining some foothold.

2. **The current blocker is support honesty, not lack of theoretical value.**
   The key issue is that `nix-router-optimized` does not currently prove that all
   modules required by its supported feature combinations are preloaded before
   lock-down.

3. **The real conflict is with recoverability and late-bound feature surfaces.**
   The highest-risk surfaces called out repeatedly were:
   - Proxmox/VM recovery assumptions
   - dynamic or feature-triggered module loading around Tailscale/WireGuard
   - Tayga / NAT64
   - nftables flowtable/offload
   - and future/experimental paths like CLAT

4. **This should not be presented as a default hardening recommendation now.**
   The panel did not support simply adding “set
   `security.lockKernelModules = true;`” to the repo’s hardening guidance as if
   it were already within the supported default boundary.

5. **If preserved at all, the right framing is advanced opt-in or
   consumer-side-only hardening.**
   There was strong agreement that the repo may eventually document or expose an
   experimental/advanced path, but only with explicit module-dependency and
   recovery warnings.

6. **The HA posture matters.**
   The current standby is still primarily valuable as a conservative
   management/recovery surface.
   Even where there was mild disagreement about whether standby is *safer* than
   the active node to lock, there was no support for recommending locked-kernel
   standby as a broad current posture.

## Real disagreements that remained

There was no major disagreement on the bottom line.

The meaningful differences were mostly about **where a future experiment would be
least risky**.

- **Codex** and **Gemini** leaned toward “if this is explored at all, it is more
  plausible on the active node only after explicit auditing, while the standby
  should stay flexible for recovery or break-glass work.”
- **GitHub Copilot CLI** was more open to “start with the standby as a consumer
  deployment experiment,” because its current management-first posture narrows
  the live feature surface.
- **DeepSeek** was somewhat more open to the idea that the standby’s smaller
  runtime surface could make it a candidate eventually, but still did not
  recommend that the repo support or advertise it now.

So the disagreement is not “should this be recommended now?”
It is “if a later experiment happens, which node would be the safer first test
surface?”

## Synthesis

The safest recorded answer for the repo today is:

- do **not** add or recommend `security.lockKernelModules = true;` as part of the
  normal router VM hardening guidance
- do **not** treat it as already inside the supported HA/recovery posture
- and do **not** imply that the current flake has audited or stabilized all
  required module dependencies

If the project wants to keep the idea alive, the best next shape is much
narrower:

1. document it only as an **advanced consumer-side hardening choice**
2. explicitly warn that VM recovery and feature compatibility may break unless
   required modules are preloaded
3. create a feature-by-feature module-dependency audit before any repo-level
   support claim
4. if a future repo option exists, keep it:
   - `false` by default
   - explicitly experimental
   - and accompanied by recovery/promotion-boundary warnings

That aligns better with the repo’s newer norm of honest support boundaries,
especially around HA and failover.

## Bottom line

`nix-router-optimized` should **not** currently add or recommend
`security.lockKernelModules = true;` for router VMs as a normal supported
hardening step.

The strongest safe position is:

- keep it outside the default support boundary for now
- optionally document it as a narrow advanced consumer choice
- and revisit only after explicit module-audit and recovery-boundary work
