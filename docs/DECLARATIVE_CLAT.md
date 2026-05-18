# Declarative CLAT-Style Design

## Status

Draft design document for work item 37.

This document defines the intended repo-native direction for a future
CLAT-style capability in `nix-router-optimized`. It is deliberately design-first:
it does **not** mean the feature is mature, implemented, or ready to present as a
normal router module today.

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

### `router-firewall`

The design should integrate with `router-firewall` through explicit optional
seams, not by assuming wide-open trust.

The feature should define:

- trusted input expectations
- translated forward-path expectations
- default-deny behavior when the required rules are absent

### HA / active-owner boundaries

This feature should be treated as **single-owner at first**.

Until the repo has a clearer active-owner model for this capability, the design
should explicitly avoid claiming HA readiness.

That means early versions should assume:

- one active router owns the control plane
- one active router owns the mapping/data-plane state
- backup / takeover behavior is future work

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

## Smallest Useful First Implementation Slice

The smallest useful first slice should prove the **design model**, not chase full
feature completeness.

Recommended first slice:

- a repo-native experimental control-plane service or helper that:
  - allocates mappings from a bounded pool
  - persists them in a declared state directory
  - applies TTL-based expiry
  - writes a deterministic mapping artifact for a dedicated Tayga instance
- plus a module-owned declarative setup for:
  - sysctls
  - dedicated interface naming
  - route ownership
  - firewall integration
- with explicit assertions that:
  - block accidental overlap with `router-nat64`
  - reject ambiguous route ownership
  - and mark the feature as experimental / not HA-ready

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
3. then scope the first bounded implementation slice as its own work item
