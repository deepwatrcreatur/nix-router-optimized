# Discussion 09: Declarative CLAT Design Review and First-Slice Boundary

**Status:** closed
**Opened:** 2026-05-18
**Participants requested:** protocol/networking panel, implementation panel, product/DX panel, GitHub Copilot

## Why this follow-up exists

Discussions 07 and 08 established the strategic direction:

- `styx46`-style functionality is conceptually in scope
- but a naïve wrapper or long-term fork identity is the wrong shape for the repo
- the preferred direction is a repo-native, declarative design effort

Work item 37 then created that design-first workstream, and
`docs/DECLARATIVE_CLAT.md` was drafted as the first concrete artifact.

This follow-up round exists to pressure-test that draft before implementation
work starts shaping the contract implicitly.

## Relevant prior context

From [`07-styx46-incorporation-boundary.md`](./07-styx46-incorporation-boundary.md):

- the underlying problem is in scope
- the current upstream shape is too operationally sharp to adopt as a normal
  first-class feature

From [`08-styx46-incorporation-strategy-and-project-identity.md`](./08-styx46-incorporation-strategy-and-project-identity.md):

- the repo should build identity around a cleaner declarative implementation
- not around “we wrapped `styx46`”
- packaging upstream may be useful tactically, but should not define the project

From [`../DECLARATIVE_CLAT.md`](../DECLARATIVE_CLAT.md):

- provisional future surface: `services.router-clat`
- explicit control-plane vs data-plane split
- Tayga acceptable as an initial bounded data-plane candidate
- bounded mapping lifetime is required
- route/sysctl/firewall/runtime-state ownership must be declarative
- coexistence must be explicit with `router-nat64`, `router-dns64`,
  `router-firewall`, and HA work

## Question for this round

The round was asked to review the current design draft as a router-grade NixOS
feature proposal and answer five concrete questions:

1. Is `router-clat` the right provisional name, or too misleading?
2. Is Tayga a sound first data-plane choice?
3. What is missing, underspecified, or risky in the design?
4. What should the next bounded implementation work item be?
5. Should the repo package upstream `styx46` now, or remain design-first?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **Gemini CLI:** substantive
- **DeepSeek API:** substantive (`deepseek-v4-flash`)
- **GitHub Copilot:** substantive

This round completed with a **full requested roster**.

## Voice summaries

### Codex CLI

- Directionally supportive of the draft, but strongest on the claim that it is
  still too soft for a router-grade first slice.
- Accepted `router-clat` only as a **provisional** name and warned against
  treating it as a settled user-facing label before implementation proves the
  semantics.
- Accepted Tayga only if it remains **disposable backend infrastructure**, not
  architectural truth.
- Strongest missing details:
  - operator-level route ownership
  - DNS semantics for A/AAAA/dual-stack/negative responses
  - mapping refresh and expiry rules
  - explicit first-slice topology assumptions
  - failure behavior
  - observability requirements
- Preferred next work item:
  a narrow **control-plane contract and topology assertions** item rather than
  live feature code.
- Rejected packaging `styx46` now because it would muddy project identity and
  create premature support pressure.

### Gemini CLI

- Treated `router-clat` as an acceptable pragmatic provisional name, with a doc
  note clarifying that this is more like centralized CLAT / SIIT-DC-like router
  behavior than an end-host mobile CLAT story.
- Considered Tayga a sound first data plane because it is already adjacent to the
  repo's transition-tooling world, but highlighted a specific risk:
  **mapping telemetry** may be too weak for safe garbage collection unless the
  design defines how “last used” state is observed.
- Strongest missing details:
  - telemetry path for mapping GC
  - DNS service integration / ownership path
  - stronger route takeover assertions
  - interface topology clarity
- Preferred next work item:
  define the persistent mapping schema and a dry-run control-plane path that can
  emit backend config without starting the live translator.
- Rejected packaging upstream for now because it would send the wrong signal for
  a repo trying to be declarative and optimized.

### DeepSeek API

- Accepted `router-clat` as usable but warned that it carries some standards and
  operator expectation risk; suggested documentation clarification and mentioned
  `nat64-clat` as an alternate naming direction.
- Considered Tayga the right first bounded choice **if** the design documents a
  clear debt ceiling and does not become Tayga-shaped.
- Strongest missing details:
  - route conflict resolution policy
  - DNS dependency / failure behavior
  - default mapping TTL and in-flight connection implications
  - topology assumptions
  - explicit failure-mode analysis
  - a tighter definition of “single-owner”
- Preferred next work item:
  implement the declarative option tree, route/conflict validation, and config
  generation path first, without committing yet to a running data plane.
- Rejected packaging upstream now; argued that design-first is cleaner and that a
  full package would create avoidable maintenance drag before the repo-native
  contract is proven.

### GitHub Copilot

- I agreed with the general direction of the design draft, but not yet with its
  current precision level.
- My strongest takeaways were:
  - `router-clat` is acceptable as a provisional lineage name, but should remain
    explicitly provisional
  - Tayga is acceptable only as an adapter/backend for the first slice
  - the next step should tighten the contract before any live feature rollout
- The design looked strongest where it separated control plane from data plane
  and weakest where it still spoke at the principle level rather than the
  operator contract level.
- The main missing details I saw matched the other seats:
  - topology boundary
  - DNS behavior and ownership
  - mapping lifecycle specifics
  - failure-mode semantics
  - observability / introspection
- I also agreed that packaging `styx46` now would blur the repo's message at the
  exact moment the project is trying to prove that it can do cleaner design work.

## First-pass convergence

Despite different emphases, all four voices converged strongly on several points.

1. **`router-clat` is acceptable only as a provisional design name.**
   No voice treated the name as a blocker, but none thought it should quietly
   graduate into a permanent promise yet.

2. **Tayga is acceptable for the first slice only if it remains a backend, not
   the feature's architecture.**
   The panel did not reject Tayga, but every voice attached a warning:
   the repo must not let Tayga's current limitations define the long-term module
   contract.

3. **The draft is directionally right but underspecified in router-grade ways.**
   The strongest convergence was that the document currently says the right kinds
   of things, but not yet at the level of operator/testable contract needed for
   implementation.

4. **The biggest missing details are concrete, not philosophical.**
   Across seats, the same gaps kept appearing:

   - topology assumptions and support boundary
   - route ownership / conflict policy
   - DNS behavior and DNS service integration
   - mapping lifecycle specifics, especially refresh and expiry
   - failure modes
   - observability / introspection requirements

5. **The next work item should narrow the contract before bringing up a live
   translator.**
   No voice argued that the repo should rush directly into a complete running
   `router-clat` service. The convergence was toward:

   - schema
   - assertions
   - config generation / dry-run behavior
   - and explicit first-slice topology definition

6. **The effort should remain design-first for now.**
   This was stronger than expected: all obtained voices opposed packaging
   upstream `styx46` immediately.

## Real disagreements that remained

The disagreements were narrower than in Discussions 07 and 08, but a few real
differences remained.

### 1. Naming risk level

All voices accepted `router-clat` provisionally, but they weighted the naming
risk differently:

- **Gemini** was the most relaxed
- **Codex** was the most cautious about letting the provisional name harden too
  early
- **DeepSeek** sat in the middle and explicitly suggested documentation
  clarification or a possible alternative naming direction

### 2. What the immediate next work item should emphasize

The panel converged on “contract before live data plane,” but differed slightly
on the center of gravity:

- **Codex** emphasized topology assertions and operator contract
- **Gemini** emphasized mapping schema and dry-run control-plane logic
- **DeepSeek** emphasized option-tree/config-generation/route validation
- **Copilot** aligned with a combined contract-first slice rather than a runtime
  slice

This is a difference in emphasis more than a strategic split.

### 3. Tayga's main risk framing

All voices accepted Tayga conditionally, but their worries differed:

- **Gemini** focused on telemetry / GC viability
- **DeepSeek** focused on documenting a debt ceiling and swap-out criteria
- **Codex** focused on hidden Tayga-shaped design drift

These concerns are compatible, but not identical.

## Final synthesis

The round's strongest conclusion is:

**The declarative CLAT draft is architecturally on the right track, but it is
not yet precise enough to serve as the direct implementation contract.**

The panel supported the current trajectory:

- repo-native design
- provisional `router-clat` naming
- explicit control-plane / data-plane split
- Tayga as an acceptable first bounded backend
- experimental single-owner support boundary

But it also converged that the next step should be **another narrowing move**,
not an expansion move.

That means the repo should do **all** of the following before a live first slice
is treated as the main task:

1. sharpen the topology boundary
2. define the route-ownership and conflict model
3. define DNS behavior and service integration expectations
4. define mapping refresh/expiry semantics
5. define required observability and failure behavior

The best next implementation item is therefore not:

- “implement `router-clat`”

but something more like:

- “define the first-slice control-plane contract, topology assertions, and
  backend artifact schema”

The round also materially changed the packaging question:

**Do not package upstream `styx46` yet.**

At this stage, packaging would create more identity blur and maintenance drag
than learning value. The repo should keep the effort design-first until the
first declarative slice lands and proves its own contract.

## Suggested next work item

Create a follow-on work item that is narrowly scoped to:

- first-slice supported topology
- mapping record schema
- backend artifact schema
- route/conflict assertions
- DNS behavior contract
- required observability/failure-mode notes

That item should be treated as the bridge between the current design doc and any
later Tayga-backed implementation slice.
