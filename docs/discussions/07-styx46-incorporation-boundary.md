# Discussion 07: Should `nix-router-optimized` Incorporate `apalrd/styx46`?

**Status:** closed
**Opened:** 2026-05-18
**Participants requested:** protocol/networking panel, implementation panel, product/DX panel, GitHub Copilot

## Relevant prior context

From [`docs/router-nat64-dns64.md`](../router-nat64-dns64.md) and the
corresponding modules:

- the repo already ships:
  - `services.router-nat64` — Tayga-based stateless NAT64
  - `services.router-dns64` — Unbound DNS64 synthesis
- current transition story is:
  - **IPv6-only clients** reaching **IPv4-only destinations**

From [`05-router-bgp-support-boundary.md`](./05-router-bgp-support-boundary.md):

- the repo already has an explicit pattern for deciding whether something should:
  - stay outside the flake
  - enter as an advanced / experimental opt-in
  - or be treated as a more mature supported wrapper
- the key standard is not “is this idea useful,” but:
  - what support burden it creates
  - whether the wrapper shape fits repo conventions
  - and whether docs / eval / boundary language are honest

From [`docs/module-authoring.md`](../module-authoring.md):

- mature router wrappers should:
  - fit the `router-<name>` module shape
  - avoid imperative conflicts with peer modules
  - work cleanly with optional integrations
  - include docs and eval coverage
  - prefer declarative system configuration over hidden runtime mutation where
    possible

## Grounding used for this round

The external subject under review was:

- [`apalrd/styx46`](https://github.com/apalrd/styx46/)

Grounding facts gathered before the round:

- `styx46` is a BSD-2-Clause Go project called **Styx**
- upstream presents it as a CLAT-like bridge for **IPv4-only legacy clients**
  reaching an **IPv6-first** world
- it:
  - listens for IPv4 DNS queries
  - resolves upstream AAAA answers
  - allocates IPv4 addresses from a configurable legacy pool
  - writes dynamic Tayga map entries
  - and returns synthetic A records to the client
- upstream README explicitly says:
  - it was made in two days
  - it has only been lightly tested
  - mappings currently never time out
  - and it should not be trusted in production
- source review also showed:
  - direct sysctl writes for IPv4/IPv6 forwarding and proxy NDP
  - direct netlink proxy-ND entry creation
  - direct process management of `tayga`
  - dynamic `tayga.conf` / `styx.map` generation
  - a route model that writes `tun-route 0.0.0.0/0`
  - an operational assumption that the host should *not* already have an IPv4
    default gateway because `styx` becomes the local gateway

That means the real decision is not “is this neat,” but:

- does this belong inside the flake at all
- and if yes, does it belong now as a module, as packaging only, as docs-only
  interop guidance, or not yet

## Question for this round

Should `nix-router-optimized` incorporate `styx46`, and if so, what is the
honest support boundary and next step?

Concretely:

1. Is `styx46` conceptually in-scope for the flake?
2. Should the repo incorporate it now?
3. If yes, in what form?
4. How does it relate to the repo's existing NAT64/DNS64 story?
5. What are the biggest risks and missing guardrails?
6. What target user and support boundary would be honest?
7. What concrete follow-up work, if any, should happen next?

## Participation record

What actually happened in this run:

- **Gemini CLI:** substantive
- **DeepSeek API:** substantive
- **Codex CLI:** requested, launched, retried, but did not return a usable
  answer in time
- **GitHub Copilot:** substantive

This round is therefore recorded as a **degraded roster**. Codex was not
simulated.

## Voice summaries

### Gemini CLI

- Strongest on the “**conceptually yes, operationally only as experimental**”
  position.
- Treated `styx46` as a legitimate complement to the repo's existing NAT64/DNS64
  transition story:
  - existing repo direction: IPv6-only -> IPv4
  - `styx46` direction: IPv4-only -> IPv6
- Recommended:
  - vendored package
  - thin `router-styx46` wrapper
  - explicit advanced / experimental labeling
- Biggest concerns:
  - no timeout behavior
  - direct imperative sysctl / routing mutation
  - destructive route assumptions
  - support burden if users confuse it with a mature transition feature

### DeepSeek API

- Strongest on the claim that `styx46` is **in scope** as a real IPv6 transition
  tool, not merely an off-topic curiosity.
- Also explicitly argued that the repo should **incorporate it now** as an
  experimental opt-in wrapper rather than only documenting it externally.
- Treated existing repo NAT64/DNS64 and `styx46` as complementary halves of a
  broader IPv6 transition toolkit.
- Still took the risks seriously:
  - upstream production disclaimer
  - no-timeout mappings
  - routing side effects
  - missing firewall integration
  - potential conflict with the repo's current Tayga/NAT64 assumptions
- Most willing to accept a first pass that is clearly labeled unstable and
  bounded by strong warnings and assertions.

### GitHub Copilot

- Agreed that `styx46` is **conceptually in scope**, because this repo already
  covers pragmatic IPv6 transition tooling rather than only pristine textbook
  router architectures.
- But was more cautious than the live seats about immediate incorporation.
- Main concern:
  the repo already has a declarative NAT64/DNS64 surface, while `styx46` today
  is a highly imperative prototype that:
  - owns Tayga directly
  - mutates sysctls and proxy-ND state at runtime
  - assumes control over IPv4 default-gateway semantics
  - and currently has indefinite mapping retention
- That makes it feel less like “another thin upstream wrapper” and more like an
  exploratory integration project that could create a misleading support signal
  if it appears too early as `router-styx46`.
- Preferred next step:
  - document the boundary and keep it on the queue
  - but defer a first-class wrapper until the repo is ready to impose stronger
    lifecycle, conflict, firewall, and route-model guardrails

## First-pass convergence

Despite the incomplete roster, the obtained voices converged on several points.

1. **`styx46` is conceptually in scope for this repo.**
   The panel did not treat it as out of bounds.
   It belongs to the same general class of IPv6 transition tooling as the repo's
   existing NAT64/DNS64 work, even though it solves the opposite traffic
   direction.

2. **`styx46` is not a mature supported router feature.**
   All voices agreed that upstream's own posture is a hard boundary signal:

   - built quickly
   - lightly tested
   - no timeout handling
   - explicitly not for production

   That rules out any honest presentation as a normal polished module.

3. **The main architectural relation is “complementary, but not the same.”**
   The round converged on the distinction:

   - repo `router-nat64` / `router-dns64`:
     - IPv6-only clients reach IPv4-only services
   - `styx46`:
     - IPv4-only clients reach IPv6 services

   So the risk is not pure duplication.
   The risk is user confusion and Tayga lifecycle conflict.

4. **The biggest risks are operational, not just cosmetic.**
   The panel strongly agreed on these concerns:

   - indefinite mapping growth
   - direct sysctl mutation
   - direct route ownership assumptions
   - proxy-ND side effects
   - dynamic Tayga process ownership outside the repo's current declarative shape
   - unclear coexistence with `router-nat64`

5. **If this ever lands, the support boundary must be explicit and severe.**
   Nobody argued for normal support status.
   At best, the current honest stance would be:

   - advanced
   - experimental
   - pre-production
   - no HA story
   - explicit warnings about route assumptions and mapping lifetime

## Real disagreements that remained

The main disagreement was not about conceptual fit. It was about **timing and
incorporation form**.

1. **DeepSeek and Gemini were willing to incorporate now as an experimental
   wrapper.**
   Their view was:

   - the repo already supports advanced transition tooling
   - the feature is genuinely useful
   - and a strongly warned experimental module is an appropriate way to expose it

2. **Copilot was more cautious on immediate wrapperization.**
   My view was:

   - the repo's current wrapper conventions assume a somewhat cleaner declarative
     boundary than `styx46` currently offers
   - shipping `router-styx46` now risks signaling a cleaner integration story
     than the upstream and code review support
   - therefore the first repo action should likely be:
     - explicit boundary documentation
     - a backlog item
     - and maybe packaging investigation
     - before a first-class router wrapper

This is a real disagreement in the round, not something to flatten away.

## Final synthesis

`styx46` is **in scope in principle** for `nix-router-optimized`, because the
repo already claims pragmatic IPv6 transition territory and `styx46` does solve
a complementary real problem.

But the current upstream maturity and operational shape are sharp enough that the
repo should **not** rush to make it look like a normal first-class router module.

The strongest synthesis from this degraded round is:

- keep `styx46` on the roadmap as a plausible future advanced feature
- do **not** present it as a supported router capability today
- and prefer a cautious next step that records the boundary honestly before
  wrapping it

That means the repo's practical recommendation is:

1. **Conceptually yes**
   - this belongs in the repo's design space

2. **Operationally not yet as a normal wrapper**
   - upstream no-timeout mappings and route/sysctl side effects are too sharp

3. **If the maintainer wants movement now, the best near-term step is boundary
   work, not immediate productization**
   - document the distinction from existing NAT64/DNS64
   - capture what prerequisites would be required for a safe experimental wrapper
   - and only then decide whether to package or wrap

If later incorporated, the honest first landing would still need to be:

- advanced / experimental
- explicit about conflict with existing Tayga use
- explicit about route ownership assumptions
- explicit that HA integration does not exist
- and explicit that the upstream itself does not yet claim production fitness

## Work items created from this round

None yet.

The panel found the concept worth tracking, but the synthesis did not yet
support creating an implementation work item before the maintainer decides
whether they want:

- docs / boundary clarification only
- packaging investigation
- or a truly experimental wrapper effort

## One-sentence verdict

`styx46` belongs inside `nix-router-optimized`'s conceptual transition-tooling
boundary, but it is presently too operationally sharp and too immature to
present as a normal first-class wrapper, so the honest next move is cautious
boundary work rather than immediate incorporation.
