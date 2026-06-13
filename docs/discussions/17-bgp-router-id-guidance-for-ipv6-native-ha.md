# Discussion 17: How Should `nix-router-optimized` Recommend BGP Router IDs for IPv6-Native HA Deployments?

**Status:** closed
**Opened:** 2026-06-13
**Participants requested:** Claude CLI, Gemini CLI, Codex CLI, and GitHub Copilot CLI

## Why this discussion exists

`nix-router-optimized` already exposes `services.router-bgp.routerId`, but the
current wording still frames it as "usually the primary LAN IP."

That is serviceable for a simple lab, but it becomes ambiguous in the exact
cases where this repo is trying to get more deliberate:

- IPv6-native deployments, where operators may no longer want to anchor identity
  to a meaningful IPv4 interface address
- HA-capable deployments, where per-node identity and shared service identity
  must stay distinct
- future flake consumers, who will read the docs as a recommendation rather than
  just a raw implementation detail

The external prompt for this round was a provider-oriented article about
structured BGP router ID numbering in IPv6-native networks:

- <https://www.swernetworks.com/blog/bgp-router-id-structuring-in-ipv6-native-networks/>

The real question for this repo is narrower:

- should the flake recommend **structured** router IDs as a convention?
- or should it recommend a **simpler explicit per-node** approach?

## Relevant current local context

From the current repo and adjacent deployment work:

- `modules/router-bgp.nix` already exposes `services.router-bgp.routerId`
- the option defaults to `null`
- `docs/router-bgp.md` already exists and treats BGP as advanced / experimental
- `tests/pro-features-smoke.nix` and examples already use explicit router IDs in
  several places
- recent HA cleanup in the deployment repo reinforced that router identity must
  be tied to the **active owner** boundary rather than casually shared
- router advertisements were just gated on the active owner in the companion
  deployment repo, which is another sign that node identity and shared service
  identity should stay separate

## Source material reviewed

- [`modules/router-bgp.nix`](../../modules/router-bgp.nix)
- [`docs/router-bgp.md`](../router-bgp.md)
- [`examples/router-bgp-proxmox-lab.nix`](../../examples/router-bgp-proxmox-lab.nix)
- [`05-router-bgp-support-boundary.md`](./05-router-bgp-support-boundary.md)
- the external article:
  <https://www.swernetworks.com/blog/bgp-router-id-structuring-in-ipv6-native-networks/>

## Participation record

What actually happened in this run:

- **Claude CLI:** substantive
- **Gemini CLI:** substantive
- **Codex CLI:** substantive
- **GitHub Copilot CLI:** substantive

This discussion is therefore recorded as a full four-seat local CLI round.

## Voice summaries

### Claude CLI

- Core recommendation:
  keep the recommendation simple and explicit rather than adopting a provider-style
  encoding scheme as the repo default.
- Strongest points:
  - the flake is not defining a provider-scale IGP architecture
  - complex structured encoding would force an arbitrary topology model onto
    future consumers
  - HA-capable deployments primarily need **distinct per-node identity**, not
    region / function semantics
- Recommended next move:
  document that HA and IPv6-native consumers should choose stable unique
  per-node IDs such as `10.255.0.1` and `10.255.0.2`, and avoid shared VIPs.

### Gemini CLI

- Core recommendation:
  use explicit per-node loopback-style IPv4 router IDs and avoid over-engineered
  structure for now.
- Strongest points:
  - BGP still wants a 32-bit identifier even in IPv6-native deployments
  - a dummy or loopback `/32` remains the simplest operational convention
  - future flake consumers benefit more from a low-friction, obvious rule than
    from an imposed numbering taxonomy
- Recommended next move:
  keep `routerId` optional for backward compatibility, but make explicit
  per-node IDs the documented best practice for HA and IPv6-native use.

### Codex CLI

- Core recommendation:
  recommend simple explicit per-node router IDs now and defer any structured
  scheme until the repo has a real multi-site routing architecture that justifies
  it.
- Strongest points:
  - the HA model already leans on **node identity vs service identity**
  - the flake should not smuggle in a broader routing architecture through
    router-id conventions
  - the wrapper is still documented as advanced, so opinionated provider-style
    defaults would be premature
- Recommended next move:
  update docs to say the router ID should be stable, explicit, and per-node,
  especially in HA pairs.

### GitHub Copilot CLI

- Core recommendation:
  this repo should not make structured BGP router ID numbering part of its
  default consumer guidance yet.
- Strongest points:
  - the present flake surface is still centered on a small FRR wrapper, not a
    general routing identity system
  - the real local risk is not "unstructured IDs"; it is accidentally tying BGP
    identity to a shared HA VIP or to a dynamic LAN address
  - simple explicit IDs align with the repo's current maturity better than an
    embedded provider-style taxonomy
- Recommended next move:
  refine the `routerId` wording and BGP docs now, and only revisit a more
  structured scheme if the repo later grows a real multi-site IGP / route
  reflector / role-taxonomy story.

## First-pass convergence

The voices converged strongly on the following points.

1. **The repo should prefer simple explicit per-node router IDs right now.**
   A recommendation like `10.255.0.1` / `10.255.0.2` is easy to understand,
   works in IPv6-native environments, and matches BGP's actual identifier model.

2. **The repo should not impose a provider-style structured numbering scheme as
   the default convention yet.**
   That would overfit the flake to a larger routing architecture it does not yet
   claim to provide.

3. **HA is the decisive local factor.**
   The most important design rule is:
   per-node router identity must stay separate from shared service identity.

4. **The documentation should be tightened immediately.**
   "Usually the primary LAN IP" is too loose because it can encourage exactly the
   wrong instinct in HA-capable deployments.

5. **A future structured scheme is not ruled out forever.**
   It is simply not the right default recommendation for this repo at its current
   scope and maturity.

## Final synthesis

- `services.router-bgp.routerId` should remain an explicit, user-controlled
  option.
- The repo should recommend a **stable unique per-node IPv4-style identifier**
  for HA-capable and IPv6-native deployments.
- The repo should explicitly warn against:
  - shared VIP-derived router IDs
  - dynamic LAN addresses as router IDs when stable peering identity matters
- The repo should **not** yet recommend provider-style function / region /
  instance encoding as the default flake convention.

## Direct follow-through from this round

This round was tight enough that the repo landed the first follow-through
immediately instead of creating a new queue item:

- tighten the `routerId` option wording in `modules/router-bgp.nix`
- tighten the router ID guidance in `docs/router-bgp.md`
- add explicit HA language that the `routerId` must stay per-node rather than
  shared with the virtual IP

## One-sentence verdict

`nix-router-optimized` should recommend simple explicit per-node BGP router IDs
for IPv6-native and HA-capable deployments, and defer any structured
provider-style numbering convention until the repo has a broader routing
architecture that truly needs it.
