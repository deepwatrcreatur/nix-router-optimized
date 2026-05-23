# Declarative CLAT-Style Design

## Status

Originally drafted for work item 37, then partially landed as the bounded
first-slice `router-clat` module in work item 38.

This document still defines the intended repo-native direction for the broader
CLAT-style capability in `nix-router-optimized`. The currently merged module is
only a first slice: it is assertion-heavy, intentionally narrow, and not yet a
claim of full runtime completeness, HA readiness, or final naming stability.

## Problem Statement

`nix-router-optimized` already supports one important IPv6 transition path:

- `router-nat64` + `router-dns64`
- IPv6-only clients reaching IPv4-only services

The missing complementary capability is:

- legacy IPv4-only clients reaching IPv6 destinations
- in networks where the router has working IPv6 upstream connectivity and wants
  to preserve service for old hosts without committing the whole LAN to
  dual-stack forever

The repo became interested in this capability after reviewing
[`apalrd/styx46`](https://github.com/apalrd/styx46/), which demonstrates that
the underlying user problem is real and technically tractable.

However, the repo's design discussions also concluded that the current upstream
shape is too operationally sharp to wrap directly as the flake's first-class
model.

## What Is Borrowed From `styx46`

The repo is borrowing the **problem framing and high-level mechanism**, not the
current implementation shape.

Useful ideas demonstrated by `styx46`:

- legacy IPv4-only clients can be helped by a local resolver that:
  - answers IPv4 DNS queries
  - prefers upstream AAAA records when available
  - assigns synthetic IPv4 addresses from a local pool
  - and maintains an IPv4<->IPv6 mapping for packet translation
- Tayga can serve as the translation data plane
- the capability belongs in the general family of pragmatic IPv6 transition tools

These ideas are valuable and in scope.

## What Must Be Rethought For This Repo

The repo should **not** inherit the following as its design model:

- direct runtime sysctl mutation from the control-plane daemon
- direct route ownership assumptions hidden inside the daemon
- direct ownership of Tayga process lifecycle inside a prototype binary
- indefinite mapping retention
- hidden proxy-ND mutation
- operational assumptions like “this host must not already have an IPv4 default
  gateway” without declarative validation and boundary language

The repo's value is supposed to come from turning that sort of sharp prototype
into a cleaner Nix-native capability.

## Proposed Capability Boundary

The intended future capability is:

- **repo-native**
- **declarative**
- **explicitly experimental at first**
- and **modularly decomposed**

The feature should be treated as a CLAT-style or legacy IPv4-to-IPv6 bridge
capability, but the repo should avoid overclaiming strict standards compliance
before the final data-plane/control-plane semantics are proven.

### Provisional naming

Use **`router-clat`** as the provisional design name for now.

Reasons:

- concise
- recognizable to people familiar with IPv6 transition tooling
- close enough to the conceptual problem
- better than naming the module after an upstream prototype (`router-styx46`)

This name remains provisional. If later implementation shows the semantics are
too far from what operators expect from “CLAT,” the user-facing name can still be
revisited before stabilization.

The project should treat the name as acceptable for design and work-item lineage,
but **not yet as a permanent user-facing promise**. Before stabilization, a
review checkpoint should explicitly confirm whether the eventual behavior is
close enough to operator expectations for “CLAT” to keep the name honestly.

### Intended module surface

The future surface should live under:

```nix
services.router-clat
```

with a design shape more like:

- `enable`
- `upstreamInterface` or equivalent route-domain reference
- `listenInterfaces`
- `legacyIpv4Pool`
- `mappingPrefix6` or equivalent IPv6-side mapped range
- `mappingTtl` / `gcInterval`
- `preferSynthesizedAnswers`
- `upstreamResolvers`
- `openFirewall` / router-firewall integration toggles
- explicit experimental guardrails

The design should **not** begin by exposing every sharp implementation detail of
the prototype. The first public surface should be the minimum needed to express
the model honestly.

## Control Plane vs Data Plane

The core design principle is:

- **control plane** and **translation data plane** must be separated

### Control plane responsibilities

The control plane is responsible for:

- answering or synthesizing DNS responses for legacy IPv4-only clients
- allocating synthetic IPv4 addresses from a bounded pool
- persisting mapping state
- expiring and garbage-collecting stale mappings
- producing deterministic mapping artifacts for the data plane
- exposing status and metrics

### Data plane responsibilities

The data plane is responsible for:

- actually translating packets based on declared mappings
- interfacing with the kernel and network stack
- forwarding traffic once mappings exist

For the first design iteration, Tayga remains an acceptable candidate data plane,
but it should be treated as a bounded dependency, not as the owner of the whole
feature model.

### Tayga debt ceiling

If Tayga is used in the first bounded slice, the repo should document upfront
that Tayga is:

- an initial backend
- not the architectural center of the feature
- and not guaranteed to remain the long-term translation engine

The repo should be willing to replace or supplement Tayga if any of the
following become true:

- mapping telemetry is too weak to support credible GC behavior
- required reload/update behavior proves unsafe or too disruptive
- throughput/latency characteristics become a clear bottleneck
- HA or ownership requirements later demand capabilities Tayga does not offer

The control-plane contract should therefore be described in backend-agnostic
terms even when Tayga is the first implementation target.

The dedicated preserved contract note is:

- [`docs/router-clat-control-plane-contract.md`](./router-clat-control-plane-contract.md)
- [`docs/router-clat-preservation-plan.md`](./router-clat-preservation-plan.md)

## Declarative Ownership Rules

The design should be explicit about who owns what.

### Mapping allocation and persistence

Mapping state should live in an explicit persistent state directory, owned by the
module and declared through systemd state mechanisms, for example:

- `/var/lib/router-clat/`

This state should include:

- current active mappings
- last-seen / last-used timestamps
- any derived mapping artifact written for the data plane

The daemon must not treat in-memory state alone as authoritative.

### Mapping expiry / garbage collection

Unlike `styx46`, the repo design requires bounded mapping lifetime.

The model should include:

- configurable mapping TTL
- periodic garbage collection
- safe data-plane reload/update on mapping removal
- explicit behavior for pinned/static mappings if those are later supported

This is non-negotiable for a router feature that wants to be credible.

The design must also define what counts as mapping activity. The first bounded
slice should not leave “last used” as an implied concept. It should state
whether mapping refresh is driven by:

- DNS lookups
- packet/flow observations
- explicit control-plane lease refresh
- or some combination

If the first slice cannot observe reliable packet-level usage safely, it should
say so plainly and keep the support boundary narrow rather than pretending that
TTL-based GC is semantically complete.

### Tayga interaction

Initial direction:

- a dedicated Tayga instance may still be used
- but the module, not an opaque prototype binary, should own:
  - config generation
  - state path
  - lifecycle
  - interface naming
  - reload behavior

The control-plane daemon should not be the hidden process supervisor for the
entire feature.

### Route ownership

The module must name its route ownership rules explicitly.

That means:

- no hidden assumption that the daemon “just becomes the IPv4 default gateway”
- no implicit takeover of existing IPv4 default routes
- no silent mutation of unrelated routing domains

The first implementation should likely require explicit route ownership on a
bounded interface set and reject ambiguous or conflicting topologies.

That should include explicit answers to questions like:

- whether the router must be the only IPv4 default gateway for the served legacy
  segment
- whether the feature is limited to directly attached L2/L3 segments
- whether policy-routing or asymmetric return paths are allowed in the first
  slice
- and what happens when another module or host-level config tries to own the
  same effective route domain

### Sysctl ownership

If the feature requires kernel forwarding or proxy-ND behavior, that must be
declared through NixOS module configuration:

- `boot.kernel.sysctl`
- or equivalent declarative network/systemd configuration

The runtime daemon should not be writing to `/proc/sys/...` directly.

### Firewall ownership

Firewall behavior should follow repo conventions:

- integrate with `router-firewall` when imported
- fall back cleanly otherwise
- use explicit rules rather than hidden assumptions

At minimum, the module should own:

- which client interfaces may use the feature
- what translated traffic is allowed toward the data plane
- and how any exposed listener ports are surfaced

## Supported Topology For The First Slice

The first implementation slice should intentionally support a **narrow topology**
and reject more ambitious shapes until the contract is proven.

Recommended initial support boundary:

- one active router
- one upstream IPv6 domain
- one bounded legacy IPv4 client domain or an explicitly listed set of LAN
  interfaces in the same policy shape
- no HA / VRRP takeover
- no multi-WAN decision logic inside the feature
- no asymmetric routing assumptions
- no hidden route takeover beyond explicitly listed client-facing interfaces

If a later implementation wants to relax any of these constraints, that should
be treated as a new design checkpoint rather than an incidental broadening.

### Normative first-slice shape

To keep the first slice honest, the design should assume all of the following:

- exactly one `upstreamInterface` participates in the CLAT path
- one or more `listenInterfaces` may be listed, but they must share the same
  policy shape and trust level
- each `listenInterface` must be directly attached to the router that owns the
  CLAT instance
- the router must already be the intended IPv4 default gateway for clients on
  those `listenInterfaces`
- the feature does **not** take over DHCP ownership by itself; address
  provisioning remains the job of whatever LAN/DHCP surface already serves those
  clients
- the first slice should not assume bridge-wide magic across unrelated routing
  domains or hidden packet interception outside the explicitly listed interfaces

If a configuration does not meet those assumptions, the first slice should
reject it rather than trying to degrade gracefully into a topology the repo has
not yet designed.

## Route Ownership and Conflict Model

The first slice should define route ownership concretely enough to drive
assertions and startup refusal.

### Ownership rules

- `router-clat` owns only:
  - its explicitly declared translation interface(s)
  - routes needed for those interface(s)
  - and forwarding behavior for explicitly listed `listenInterfaces`
- `router-clat` does **not** silently install or replace unrelated host-wide
  IPv4 default routes
- `router-clat` may only operate on client segments where the router is already
  meant to be the IPv4 default gateway
- `router-clat` must not claim the same effective route/interface domain as
  another feature unless that coexistence has been designed explicitly

### First-slice assertions

The first bounded implementation should reject configurations where:

- `upstreamInterface` is unset or ambiguous
- a listed `listenInterface` is also being used as another feature's translation
  interface
- route ownership on the served client segment is ambiguous
- the configured IPv4 pool overlaps with another CLAT/NAT64/host-local range
  already claimed by the router
- the feature is enabled in a configuration that implies HA or multi-WAN
  behavior the first slice does not support

The startup model should be:

- fail evaluation where possible
- fail service startup where runtime facts are required
- never silently proceed with guessed ownership

## DNS Behavior Contract

The first slice should make DNS behavior explicit enough that operators know
what the control plane is actually promising.

At minimum, the design should define:

- whether `router-clat` is acting as:
  - an authoritative synthesizer for a bounded client set
  - a forwarding resolver with synthesis capability
  - or a sidecar that depends on another DNS service
- what happens for:
  - AAAA-only upstream answers
  - A-only upstream answers
  - dual-stack upstream answers
  - NXDOMAIN / NODATA responses
- whether synthesized A responses clamp or inherit TTLs
- whether mappings are keyed primarily by destination IPv6, DNS name, or another
  stable identity
- whether local overrides / split-horizon zones must be provided by another DNS
  service

The first slice should prefer explicit dependency language over vague
coexistence claims. If this feature depends on another local DNS service for
part of the resolution path, that should be stated clearly.

### First-slice DNS stance

For the first bounded slice, `router-clat` should be treated as a
**forwarding resolver with synthesis capability for an explicitly bounded client
set**, not as a general-purpose authoritative DNS replacement.

That means:

- it forwards upstream using explicitly configured `upstreamResolvers`
- it synthesizes answers only for the clients and interfaces that are explicitly
  assigned to the feature
- it should not silently rewrite global router DNS ownership outside that scope

### First-slice answer policy

The first slice should behave as follows:

- **AAAA-only upstream answer**
  - choose one IPv6 destination deterministically
  - allocate or reuse a synthetic IPv4 mapping
  - return a synthesized A answer
- **A-only upstream answer**
  - return the upstream A answer unchanged
  - do not allocate a synthetic mapping
- **Dual-stack upstream answer**
  - by default, return the upstream A answer unchanged
  - only prefer a synthesized answer when the configuration explicitly opts into
    that behavior
- **NXDOMAIN / NODATA**
  - pass the upstream result through unchanged
  - do not allocate a mapping
- **Synthesis required but backend/control-plane contract unavailable**
  - fail loud with `SERVFAIL`
  - do not emit a synthetic A that the backend cannot honor safely

### TTL policy

Synthesized A answers must never outlive the mapping they refer to.

For the first slice, the synthesized TTL should be bounded by:

- the effective mapping lifetime remaining
- the upstream AAAA TTL when one exists
- and any explicit module-side TTL clamp introduced by configuration

If the implementation cannot preserve that relationship, it should shorten TTLs
rather than overstate freshness.

## Mapping Contract

The first slice needs a more explicit mapping contract than “bounded pool + GC.”

At minimum, the contract should define:

- the stable record shape for persisted mappings
- what fields are authoritative
- what refreshes `lastSeen` / `lastUsed`
- how mappings behave when multiple AAAA answers exist
- whether recycled IPv4 assignments may break existing long-lived flows
- and whether the first slice explicitly optimizes for short-lived
  destination-initiated client traffic rather than arbitrary protocol fidelity

If active-flow preservation cannot be guaranteed under mapping expiry, the
support boundary should say so directly.

### First-slice mapping identity

The first slice should treat **destination IPv6** as the primary identity for a
dynamic mapping, with DNS names recorded as supporting metadata rather than as
the sole key.

This keeps the control-plane contract closer to the translation problem and
avoids making the public model depend entirely on resolver-side naming trivia.

### Deterministic destination selection

When an upstream answer contains multiple AAAA records, the first slice should
use a deterministic rule:

1. if an existing unexpired mapping already points to one of the returned IPv6
   addresses for that name, reuse it
2. otherwise sort the returned IPv6 addresses deterministically and choose the
   first entry

This is intentionally conservative. The goal of the first slice is determinism
and inspectability, not sophisticated traffic distribution.

### Proposed persisted mapping record

The first slice should persist records in a backend-agnostic shape such as:

```json
{
  "version": 1,
  "ipv4": "192.0.2.10",
  "ipv6": "2001:db8::10",
  "names": ["example.internal"],
  "createdAt": "2026-05-18T04:00:00Z",
  "lastDnsAnswerAt": "2026-05-18T04:05:00Z",
  "lastFlowSeenAt": null,
  "expiresAt": "2026-05-18T04:10:00Z",
  "state": "active"
}
```

Authoritative fields for the first slice should be:

- `ipv4`
- `ipv6`
- `createdAt`
- `expiresAt`
- `state`

Helpful but non-authoritative supporting metadata may include:

- associated DNS names
- last DNS synthesis time
- optional packet/flow observation time if the implementation can collect it

### Refresh and expiry semantics

For the first slice:

- emitting a synthesized DNS answer refreshes `lastDnsAnswerAt`
- `lastFlowSeenAt` is optional and should remain `null` unless the
  implementation has a trustworthy observation path
- `expiresAt` is the time after which the control plane must stop advertising
  that synthetic mapping as fresh
- expired mappings are eligible for backend removal and IPv4 reuse

This implies an honest limitation:

- the first slice does **not** guarantee preservation of long-lived flows beyond
  mapping expiry
- it is optimized for bounded, client-initiated reachability rather than for
  pretending to offer perfect session persistence

## Backend Artifact Contract

The first slice should define a backend-neutral artifact contract before it
renders any Tayga-specific config.

### Public artifact shape

The control plane should emit a deterministic artifact with semantics closer to:

```json
{
  "version": 1,
  "generatedAt": "2026-05-18T04:00:00Z",
  "instance": "default",
  "translationInterface": "clat0",
  "upstreamInterface": "wan0",
  "listenInterfaces": ["lan0"],
  "mappings": [
    {
      "ipv4": "192.0.2.10",
      "ipv6": "2001:db8::10",
      "expiresAt": "2026-05-18T04:10:00Z",
      "state": "active"
    }
  ]
}
```

That artifact should be the public contract the rest of the module reasons
about.

### Backend-specific rendering rule

Backend-specific steps such as Tayga config generation should be a renderer over
that artifact, not the source of truth itself.

This keeps the first slice from becoming Tayga-shaped in:

- persisted state
- option semantics
- and test fixtures

## Coexistence and Conflict Rules

The design must explicitly define coexistence with existing router features.

### `router-nat64`

`router-clat` and `router-nat64` are conceptually complementary, but they should
not casually share the same Tayga lifecycle or pool semantics.

The initial design should assume:

- separate instance ownership
- separate interface names
- separate state/config paths
- explicit assertions against accidental overlap in pools or interfaces

If later work proves safe combined operation, that can be added intentionally.
It should not be assumed at the start.

### `router-dns64`

`router-dns64` is not the same feature, but the two capabilities interact at the
story level:

- `router-dns64`: synthesize AAAA for IPv6-only clients
- `router-clat`: synthesize A-like reachability for IPv4-only legacy clients

Docs must explain this distinction clearly so the repo's transition toolkit feels
coherent instead of ad hoc.

The first implementation should also avoid implying that `router-dns64` is a
hard dependency unless the design actually chooses that path. The support
boundary should clearly say whether `router-clat`:

- depends on an existing repo DNS module
- integrates with one optionally
- or owns a narrow DNS path itself

### `router-firewall`

The design should integrate with `router-firewall` through explicit optional
seams, not by assuming wide-open trust.

The feature should define:

- trusted input expectations
- translated forward-path expectations
- default-deny behavior when the required rules are absent

For the first slice, the default posture should be:

- only explicitly listed `listenInterfaces` may originate CLAT-served traffic
- only the declared translation interface/back-end path may carry translated
  flows for this feature
- if required firewall rules cannot be installed or derived, the feature should
  fail closed rather than assuming permissive forwarding

### HA / active-owner boundaries

This feature should be treated as **single-owner at first**.

Until the repo has a clearer active-owner model for this capability, the design
should explicitly avoid claiming HA readiness.

That means early versions should assume:

- one active router owns the control plane
- one active router owns the mapping/data-plane state
- backup / takeover behavior is future work

For early work, “single-owner” should be read concretely as:

- one NixOS host
- one active control-plane instance
- one active translation backend instance per configured feature instance
- and no failover promise if that owner disappears

## Repo-Local vs Upstream Responsibilities

### What should remain repo-local

These are part of the repo's own identity and should not be treated as upstream
responsibility:

- NixOS module shape
- declarative state/lifecycle ownership
- router-firewall integration
- route/sysctl ownership model
- HA boundary model
- eval and VM-test strategy
- documentation on support boundary and operational verification

### What could be upstreamed

If the repo later learns useful generic lessons, these could plausibly be fed
upstream or to related projects:

- bug fixes
- mapping expiry ideas
- improved config docs
- tests for generic IPv4<->IPv6 mapping correctness
- small generic improvements to a reference prototype

But the repo should not assume that the upstream project wants, or is structured
to accept, the repo's full declarative Nix-native design.

## Council / Discussion Checkpoints

This workstream should deliberately use the council rather than treating design
as front-loaded and implementation as silent.

Recommended checkpoints:

1. **Checkpoint A — design acceptance**
   - review this document
   - decide whether `router-clat` remains the provisional name
   - decide whether Tayga remains the initial data plane

2. **Checkpoint B — first implementation slice review**
   - once a minimal bounded implementation slice exists
   - verify that ownership boundaries still match the design

3. **Checkpoint C — first user-facing surface review**
   - before any README feature-list promotion
   - reassess support boundary and wording

4. **Checkpoint D — HA / active-owner review**
   - only after the single-owner model is stable
   - decide whether any HA work should begin

## Failure Behavior and Observability

The first slice should explicitly define what operators can inspect and what
happens when parts fail.

### Minimum observability

At minimum, the repo should aim to expose:

- current active mapping records
- mapping expiry times or last-used timestamps
- backend health
- DNS synthesis decisions or rejection reasons
- topology/assertion failures at evaluation or service startup

### Minimum failure-behavior questions

Before implementation broadens, the design should state what happens when:

- the control plane is down but backend state still exists
- the backend is down but DNS synthesis is still answering
- the mapping artifact cannot be written or reloaded
- the state directory is corrupted or missing
- the upstream IPv6 path disappears
- the topology assertions no longer hold after configuration changes

The first slice should prefer **fail-closed and loud** behavior over silent
partial success where the control plane and translation backend drift apart.

### First-slice failure policy

To make that concrete, the first slice should behave as follows:

- if the control plane cannot render a backend artifact, it must not publish new
  synthesized answers
- if the backend cannot load the current artifact, the control plane must treat
  synthesis as unavailable for names that depend on translation
- if the state directory is unreadable or corrupt, startup should fail loudly
  rather than discarding state silently
- if the upstream IPv6 path disappears, existing state may remain visible for
  inspection, but new synthesis should fail rather than claiming usable
  reachability
- if topology assertions fail after configuration changes, the unit should fail
  and surface the reason explicitly

### First-slice observability surface

The first slice should aim to expose inspectable machine-readable state such as:

- a persisted mapping file under `/var/lib/router-clat/`
- a rendered backend artifact under `/run/router-clat/`
- a status or health summary indicating:
  - backend readiness
  - last successful render/reload time
  - mapping counts
  - assertion failures
  - synthesis-disabled reasons

Human-friendly tooling can come later, but the first slice should at least leave
enough durable state that operators and later modules can understand what it is
doing.

## Validation Surface For The First Slice

Before a live translator becomes the main story, the repo should validate the
contract with cheap deterministic surfaces.

Recommended first validation scope:

- eval-time assertions for unsupported topologies and overlapping pool/interface
  ownership
- deterministic fixture-based tests for mapping selection and expiry decisions
- deterministic rendering tests from persisted mapping records to backend-neutral
  artifacts
- backend renderer tests that prove Tayga config generation is derived from the
  artifact rather than acting as the artifact
- startup/service tests that assert fail-closed behavior when artifact
  generation, reload, or state read fails

## Smallest Useful First Implementation Slice

The smallest useful first slice should prove the **design model**, not chase full
feature completeness.

Recommended first slice:

- a repo-native experimental control-plane contract that defines:
  - the supported first-slice topology
  - the persistent mapping record shape
  - mapping refresh and expiry semantics
  - the deterministic backend artifact schema
- plus a module-owned declarative setup for:
  - dedicated interface naming
  - route/conflict assertions
  - firewall integration points
  - experimental support-boundary gating
- plus a dry-run/config-generation path that can:
  - validate the topology
  - render backend artifacts deterministically
  - and expose assertion failures without requiring a running translator
- with a Tayga adapter as the initial backend target, not the source of the
  public contract

This first slice does **not** need to solve every possible topology.
It needs to prove that the repo can own the capability declaratively and safely.

## Support Boundary for Early Work

Before stabilization, the feature should be documented as:

- experimental
- not HA-ready
- intended for advanced operators
- subject to interface / route-model changes
- and not yet part of the repo's default “polished router capability” story

The repo should avoid adding it to broad feature marketing until:

- state lifecycle is clearly bounded
- conflict rules are enforced
- and the first implementation slice has explicit validation coverage

## Why This Matters For Project Identity

This work is not just about one transition feature.

It is a test of whether `nix-router-optimized` can become the place where:

- sharp router/networking prototypes are examined critically
- the useful parts are extracted
- and the resulting capability is rebuilt in a clean Nix-native shape

That is a stronger long-term project identity than:

- merely wrapping upstream tools
- or merely shipping demos

## Immediate Next Step

The next step is **not** to rush an implementation branch that looks like a thin
wrapper.

The next step is:

1. review and refine this design boundary
2. decide whether the provisional `router-clat` naming is acceptable
3. scope the first bounded implementation slice as its own work item
4. keep upstream `styx46` as a reference point only until that slice exists
