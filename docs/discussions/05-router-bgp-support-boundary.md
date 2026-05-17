# Discussion 05: Should `nix-router-optimized` Support BGP as a Flake Option?

**Status:** closed
**Opened:** 2026-05-16
**Participants requested:** protocol/networking panel, product/DX panel, implementation panel, GitHub Copilot

## Relevant prior notes

From [`modules/router-bgp.nix`](../../modules/router-bgp.nix):

- The repo already ships a thin `services.router-bgp` wrapper over FRR `bgpd`.
- Current exposed options are:
  - `asn`
  - `routerId`
  - `neighbors.<ip>.remoteAs`
  - `neighbors.<ip>.description`
  - `neighbors.<ip>.nextHopSelf`
  - `networks`
- The module opens TCP `179` via `networking.firewall.allowedTCPPorts`.

From [`tests/pro-features-smoke.nix`](../../tests/pro-features-smoke.nix):

- There is already a minimal eval check ensuring:
  - `services.frr.bgpd.enable = true`
  - firewall TCP port `179` is opened

From [`README.md`](../../README.md):

- BGP is already listed in the feature list and has a short example snippet.
- That makes the current support boundary ambiguous: the feature is visible, but
  not documented or validated to the same standard as more mature wrappers.

From [`docs/module-authoring.md`](../module-authoring.md):

- Mature router wrappers should include:
  - dedicated `docs/router-<name>.md`
  - integration notes
  - examples
  - focused eval coverage
  - safe optional integration with `router-firewall`

From [`03-router-backup-standby-and-shared-wan.md`](./03-router-backup-standby-and-shared-wan.md):

- HA work is converging on a **shared capability vs active ownership** split.
- That matters for BGP because a backup router must not blindly present active
  routing identity before promotion boundaries are explicit.

## Question for this round

Should `nix-router-optimized` support BGP as an option for flake users, and if
so, what should the repo do next?

Please answer concretely:

1. Is BGP a feature the flake should keep and improve?
2. Is the current module mature enough to count as a supported option?
3. Who is the real target user right now?
4. What are the most important missing guardrails?
5. What concrete follow-up work items should be created?

## Round 1 highlights

### Protocol / networking panel

- Core recommendation: **keep BGP, but do not treat it as a generally supported
  router feature yet**.
- BGP is genuinely useful for advanced users:
  - Proxmox clusters
  - k8s / lab routing
  - small internal dynamic-routing topologies
- It is **not** a default-value feature for typical home/small-business users.
- Biggest protocol gaps today:
  - no neighbor authentication
  - no explicit IPv6 address-family support
  - no import/export route policy surface
  - no story for BGP ownership during HA promotion
- The current module is acceptable for trusted internal lab peering, but not for
  anything that should be described as production-ready HA routing.
- Status: `[satisfied-conditional: keep the module, but label it advanced and incomplete]`

### Product / DX panel

- Core recommendation: **the repo should stop implying stronger support than it
  actually provides**.
- Evidence of maturity already present:
  - exported flake module
  - README mention
  - minimal eval coverage
- Evidence of immaturity still obvious:
  - no `docs/router-bgp.md`
  - no example under `examples/`
  - no clear support boundary in docs
  - no focused validation of optional `router-firewall` integration
- By this repo's own conventions, the module is currently closer to
  **experimental / advanced opt-in** than fully supported.
- The first follow-ups should be:
  - document the support boundary
  - align implementation with module-authoring conventions
  - add guardrails around HA expectations
- Status: `[satisfied]`

### Implementation panel

- Core recommendation: **current implementation is a solid thin wrapper, but far
  too narrow to advertise as fully supported**.
- Strengths:
  - small, understandable option surface
  - correct FRR `bgpd` enablement
  - basic neighbor rendering
  - import-safe `mkIf cfg.enable`
- Risky omissions:
  - firewall integration uses `networking.firewall` directly rather than the
    repo's optional `router-firewall` contract
  - no assertions for obviously bad combinations or missing operational data
  - no per-neighbor secret-file authentication support
  - no bounded route-policy hooks
  - no explicit story for combined `router-bgp` + `router-ha`
- The implementation panel's strongest warning was that BGP and HA should not be
  presented as compatible until active-owner boundaries are explicit.
- Status: `[satisfied]`

## First-pass convergence

The round converged on the following points.

1. **Yes, the flake should keep BGP as an option.**
   There is real value in an opt-in BGP wrapper for advanced homelab and small
   infrastructure users.

2. **No, the current BGP module is not mature enough to count as a fully
   supported option yet.**
   It is best described as an **advanced / experimental opt-in** feature.

3. **The current real target user is an advanced operator, not the typical
   router-flake user.**
   Good current fit:
   - internal lab peering
   - Proxmox / hypervisor route exchange
   - controlled cluster use

   Poor current fit:
   - generic home-router users
   - users expecting polished HA behavior
   - users needing production-quality route policy and peer hardening

4. **The repo needs two different kinds of follow-up:**
   - support-boundary / DX cleanup
   - real routing-capability / guardrail work

5. **HA interaction is the most important architectural warning.**
   The repo's HA work is converging on "shared capability, single active owner."
   BGP should follow that same ownership model rather than letting both nodes
   present active routing identity casually.

## Final synthesis

- `router-bgp` should remain in the flake.
- It should **not** yet be marketed or implied as a mature default feature.
- The right near-term stance is:
  - keep it opt-in
  - document it explicitly as advanced / incomplete
  - tighten implementation against repo conventions
  - add explicit HA boundary language and guardrails
- After that baseline cleanup, the next real capability work should focus on:
  - neighbor authentication
  - IPv6 / address-family support
  - bounded route-policy controls

## Work items created from this round

- [`31-router-bgp-support-boundary-and-docs.md`](../work-items/31-router-bgp-support-boundary-and-docs.md)
- [`32-router-bgp-firewall-and-validation.md`](../work-items/32-router-bgp-firewall-and-validation.md)
- [`33-router-bgp-ha-boundaries-and-guardrails.md`](../work-items/33-router-bgp-ha-boundaries-and-guardrails.md)
- [`34-router-bgp-auth-afi-and-policy.md`](../work-items/34-router-bgp-auth-afi-and-policy.md)

## One-sentence verdict

`nix-router-optimized` should keep BGP as an advanced opt-in feature, but it is
not yet mature enough to present as a broadly supported router option until the
repo adds clearer support boundaries, better validation, explicit HA guardrails,
and a stronger routing capability surface.

## Real CLI rerun

The first version of this discussion was a Copilot-synthesized round informed by
repo context. The maintainer then explicitly asked for the real voices of the
available agent CLIs.

Available in this environment:

- Claude CLI
- Gemini CLI
- Codex CLI

Unavailable in this environment:

- DeepSeek CLI

So the rerun below records the actual responses from the installed CLIs and
leaves the DeepSeek seat explicitly empty rather than simulating it.

### Claude CLI

- `Core recommendation`
  - Yes — BGP belongs as an optional, well-documented wrapper.
  - The thin-wrapper approach is correct, but the repo should not reinvent
    routing policy.
- `What is already true`
  - `router-bgp.nix` wraps FRR `bgpd`
  - TCP `179` is opened
  - the module is exported and included in the default bundle
  - the README mentions it
  - a minimal eval test already exists
- `Biggest gaps`
  - no `docs/router-bgp.md`
  - no `router-firewall` zone-aware integration
  - no MD5 / TCP-AO neighbor authentication option
  - no AFI / SAFI support
  - no route-map or prefix-list primitives
  - eval coverage is still narrow
- `HA interaction`
  - backup routers must not advertise BGP identity before promotion
  - the wrapper should gate on an explicit active-owner signal or at least
    document that enabling BGP implies active participation
- `Recommended next work`
  - docs and boundary statement
  - `router-firewall` integration
  - neighbor authentication and validation
  - HA guardrails
  - AFI / SAFI and basic policy options

### Gemini CLI

- `Core recommendation`
  - Yes, BGP should remain a supported option in principle, but the immediate job
    is to mature the existing implementation to repo standards.
- `What is already true`
  - thin FRR `bgpd` wrapper already exists
  - core options are exposed
  - TCP `179` is auto-opened
  - minimal evaluation and README coverage are already present
- `Biggest gaps`
  - no dedicated `docs/router-bgp.md`
  - no robust example configuration
  - no focused advanced evaluation coverage
  - port `179` is opened globally rather than through optional
    `router-firewall` integration
- `HA interaction`
  - BGP must respect the shared-capability vs active-owner split
  - standby routers are risky if they can present active routing identity before
    explicit promotion
- `Recommended next work`
  - write `docs/router-bgp.md`
  - add stronger examples
  - refactor firewall integration
  - expand eval coverage
  - add strict HA guardrails

### Codex CLI

- `Core recommendation`
  - Yes: keep BGP support exposed as an option, but treat the current module as
    an early wrapper rather than a mature router capability.
  - Do not expand adoption claims yet.
- `What is already true`
  - the flake already ships a thin FRR wrapper
  - users can set `asn`, `routerId`, neighbor attributes, and `networks`
  - TCP `179` is opened
  - the module is exported, bundled, documented briefly, and minimally tested
- `Biggest gaps`
  - no dedicated `docs/router-bgp.md`
  - eval coverage only proves enablement and port exposure
  - the wrapper still misses mature repo conventions like focused examples and
    safe optional `router-firewall` integration
- `HA interaction`
  - BGP should align with the shared-capability vs active-owner split
  - backup nodes should not present active routing identity by default
  - that implies conservative defaults and explicit HA guidance before calling
    the feature production-ready
- `Recommended next work`
  - add `docs/router-bgp.md` with limits, examples, and HA caveats
  - add focused eval coverage for neighbor rendering, `networks`, and firewall
    behavior
  - add safe optional `router-firewall` integration
  - revisit defaults and docs through the HA model

### Rerun takeaway

The real CLI rerun materially confirmed the earlier synthesis rather than
reversing it:

- all three available CLIs said **keep BGP**
- none of them treated the current module as broadly mature
- all three emphasized:
  - dedicated BGP docs
  - better validation / tests
  - proper `router-firewall` integration
  - explicit HA ownership boundaries

The main additional emphasis from Claude was that the next capability tier
should probably include authentication plus AFI / SAFI and basic policy
primitives, not just docs cleanup.
