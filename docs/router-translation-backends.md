# Router Translation Backends

Last updated: 2026-05-26

## Objective

Make the repo's NAT64 / CLAT backend boundary explicit enough that:

- operators can tell what exists today
- contributors can tell which Tayga details are implementation details
- and any future Jool work has to preserve a documented contract instead of
  silently becoming a new de facto ABI

## Current State

Today, the repo's translation story is:

- `router-nat64` is the current **PLAT-equivalent** surface
- `router-dns64` is the companion DNS64 surface for synthesized AAAA answers
- `router-clat` is the customer-side / legacy-IPv4 translation slice
- the current end-to-end translation path is **Tayga-backed**

That means NAT64/PLAT is not “missing.” It already exists today through
`router-nat64`.

What is still missing is a fully explicit **translation-backend boundary** that
separates:

- public module semantics
- public control-plane/runtime artifacts
- and Tayga-specific implementation details

## Current Supported Backend

The current supported backend is:

- **Tayga**

Current repo stance:

- Tayga remains the default and only supported NAT64 backend
- Tayga is also the current runtime backend for the bounded `router-clat` slice
- NAT64 and CLAT now share an internal translation-backend adapter helper so
  backend-specific interface, lifecycle, and config details are not duplicated
  across modules
- future backends must preserve the repo's declared contract instead of changing
  operator-facing semantics silently

Current repo non-stance:

- there is no claim yet that Jool has parity
- there is no claim yet that kernel-space alone makes Jool automatically better
- there is no claim yet that the current translation story is backend-neutral in
  every artifact and service name

## Public Surfaces Versus Implementation Details

### Public repo-facing surfaces

These are the parts contributors and operators should treat as the durable
surface:

- `services.router-nat64` option intent
- `services.router-dns64` option intent
- `services.router-clat` option intent and bounded support language
- translation prefix and pool inputs
- firewall integration expectations
- status/observability semantics exposed to operators
- backend-neutral CLAT control-plane artifact semantics documented in
  [`router-clat-control-plane-contract.md`](./router-clat-control-plane-contract.md)

### Current implementation details

These are allowed to remain Tayga-specific today:

- `services.tayga`
- `/etc/router-clat/tayga.conf`
- `router-clat-tayga.service`
- the current internal adapter implementation in
  `modules/router-translation-backend-lib.nix`
- exact Tayga config rendering and reload behavior
- Tayga-specific health checks

Those details are real implementation choices, but they should not be mistaken
for the permanent public repo contract.

## Minimum NAT64 Backend Contract

Any future NAT64 backend must satisfy at least the following contract.

### 1. Address and prefix inputs

The backend must accept, directly or via an adapter:

- one NAT64 IPv6 prefix
- one IPv4 mapping pool
- one router-owned translation IPv4 address
- one router-owned translation IPv6 address or equivalent translation-endpoint
  identity

The repo contract is about these semantics, not about one backend's exact config
syntax.

### 2. Interface and lifecycle expectations

The backend path must define clearly:

- which interface or device represents the translation path
- how that interface is created or owned
- how routes for the translation prefix/pool are installed
- how systemd lifecycle and reload/apply sequencing work

The current implementation uses Tayga and `nat64` / `clat0`-style interfaces.
A future backend may differ internally, but the operational lifecycle must be
equally explicit.

### 3. MTU, fragmentation, and MSS expectations

A backend path must document:

- whether it depends on kernel PMTU behavior
- whether fragmentation handling differs from Tayga
- whether MSS clamping is required, recommended, or irrelevant
- any operational caveats for tunnels or reduced-MTU WANs

The repo should not switch translation backends while leaving packet-size
behavior implicit.

### 4. Firewall integration points

A backend path must still provide an explicit answer for:

- what interface or traffic class `router-firewall` should allow
- how translation-path forwarding rules are expressed
- whether any backend-specific service/control ports need protection

The contract is “translation traffic is integrated intentionally with the
firewall,” not “the literal string `nat64` appears forever.”

### 5. Observability and status surfaces

A backend path must preserve operator-meaningful status:

- whether the backend is healthy
- whether translation-dependent synthesis is currently available
- which configured prefix/pool is active
- which service/unit or adapter is responsible for runtime ownership

If backend names change, operator-visible status must still remain coherent and
honest.

### 6. Artifact boundaries

The repo should distinguish:

- backend-neutral public artifacts that future implementations must preserve
- backend-specific rendered artifacts that may change with the adapter

Current CLAT precedent:

- backend-neutral mapping/status semantics are documented publicly
- Tayga config rendering is downstream implementation detail

NAT64 should follow the same pattern rather than treating one Tayga config shape
as the public long-term contract.

## Backend Selection Decision

The correct long-term location for translation-backend selection is:

- **a shared translation-backend contract**, not two unrelated selectors

Why:

- `router-nat64` and `router-clat` are two sides of the same broader
  translation story
- they share firewall/runtime/observability concerns
- a backend change should not force two drifting user-facing abstractions for
  what is conceptually one translation backend family

What this means today:

- the repo should **not** add an ad hoc Jool selector only to `router-clat`
- the repo should also avoid pretending `router-nat64` can grow backend options
  independently with no shared contract
- the current hardwired Tayga default is acceptable until a shared contract is
  ready to support a second backend honestly

## Jool Stance

Jool is a plausible future backend candidate, but the current repo stance is:

- Jool is an **evaluation/spike candidate**
- Jool is **not** a supported replacement path yet
- Jool should not silently become the default because it is kernel-space

Before a Jool path could be promoted beyond a spike, the repo would need:

- packaging and maintenance confidence
- parity for the required prefix/pool/runtime semantics
- explicit firewall and lifecycle integration
- observability parity
- docs that state the operational tradeoffs clearly

## What A Bounded Jool Spike Would Be Allowed To Do

A future bounded spike may:

- document packaging and service-model constraints
- prototype a backend adapter behind an explicit experimental selector
- compare runtime/operational differences against the current Tayga path

A bounded spike must not:

- replace Tayga as the default supported path silently
- erase Tayga-specific tests before a backend-neutral preservation layer exists
- widen the repo's support promise beyond “experimental evaluation”

## Current Recommendation

The repo should keep this stance until a real second backend exists:

- `router-nat64` remains the present PLAT-equivalent surface
- `router-clat` remains the bounded customer-side translation slice
- Tayga remains the current supported backend
- the shared translation-backend contract is the right abstraction target
- Jool remains a spike/evaluation topic, not a default migration
