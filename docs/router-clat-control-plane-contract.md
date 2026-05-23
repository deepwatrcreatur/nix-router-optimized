# router-clat Control-Plane Contract

## Status

Contract version: `v1`

This note freezes the first backend-neutral public contract for the
`router-clat` control plane. It defines the behavior that future
implementations must preserve even if the current Python daemon, Tayga adapter,
or repository layout changes.

It does **not** make the CLAT feature generally GA. It only separates
contractual behavior from incidental implementation details in the current first
slice.

## Scope

This contract covers:

- desired-state input expected by the control plane
- durable mapping/state record semantics
- backend-neutral artifact generation
- reload/apply expectations
- runtime status and degraded-state reporting
- adapter capability and failure boundaries

This contract does **not** freeze:

- the current Python file layout
- a particular Elixir module/file layout
- exact Tayga config syntax as a public API
- repository split decisions
- HA/failover behavior beyond the current single-owner boundary

## Contract Layers

The project should distinguish three layers clearly.

### Public control-plane contract

This is the durable boundary future implementations must preserve:

- mapping identity and refresh semantics
- backend-neutral artifact schema
- DNS synthesis classes and failure behavior
- state persistence requirements
- status and degraded-state fields

### Backend adapter details

These remain implementation details:

- Tayga config rendering
- Tayga reload procedure
- backend-specific readiness checks
- backend-specific limitations

The adapter may change as long as it still consumes and honors the public
contract.

### NixOS module integration

These are repo-local concerns:

- option shape under `services.router-clat`
- interface naming and route ownership
- systemd lifecycle
- firewall integration
- support-boundary assertions and warnings
- explicit non-default control-plane selector wiring

These matter operationally, but they are not the same thing as the control
plane contract itself.

## Desired-State Input Contract

The first-slice control plane assumes explicit desired state with at least:

- one configured instance name
- one upstream interface
- one or more listen interfaces
- one IPv4 mapping pool
- one IPv6 mapping prefix
- one mapping TTL
- one GC interval
- one set of upstream resolvers
- one persistent state directory
- one runtime artifact path
- one runtime status path

Version `v1` keeps the ownership model narrow:

- one NixOS host
- one active control-plane instance per configured feature instance
- one active backend instance per configured feature instance
- no HA/failover promise

## Durable Mapping Contract

### Primary identity

For dynamic mappings, the primary identity is the destination IPv6 address.

DNS names are supporting metadata, not the sole identity key.

### Persisted record shape

The preserved record shape for `v1` is:

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

Authoritative fields:

- `ipv4`
- `ipv6`
- `createdAt`
- `expiresAt`
- `state`

Supporting but non-authoritative metadata:

- `names`
- `lastDnsAnswerAt`
- `lastFlowSeenAt`

### Refresh semantics

Version `v1` preserves these semantics:

- emitting a synthesized DNS answer refreshes `lastDnsAnswerAt`
- `lastFlowSeenAt` may remain `null` unless a trustworthy flow-observation path
  exists
- `expiresAt` is the hard freshness boundary for the mapping
- expired mappings become eligible for backend removal and IPv4 reuse

### Deterministic selection

When multiple AAAA answers are available:

1. reuse an existing unexpired mapping if one already targets one of those IPv6
   addresses
2. otherwise sort deterministically and choose the first address

This is part of the public contract because preservation tests need stable
selection behavior across implementations.

### Honest limitation

The first slice does **not** guarantee long-lived flow preservation beyond
mapping expiry. The contract is optimized for bounded client-initiated
reachability rather than indefinite session survival.

## DNS Behavior Contract

The first slice is a **forwarding resolver with synthesis capability for an
explicitly bounded client set**.

It is not a general-purpose authoritative DNS replacement.

Preserved answer classes:

- AAAA-only upstream answer:
  choose one IPv6 destination deterministically, allocate or reuse a mapping,
  and return a synthesized A answer
- A-only upstream answer:
  return upstream A unchanged, allocate no synthetic mapping
- dual-stack upstream answer:
  return upstream A unchanged unless configuration explicitly prefers synthesis
- NXDOMAIN / NODATA:
  pass through unchanged, allocate no mapping
- synthesis required but backend unavailable:
  fail loud with `SERVFAIL`, do not emit a synthetic answer the backend cannot
  honor

### TTL policy

Synthesized A answers must never outlive the mapping they refer to.

For `v1`, synthesized TTL is bounded by:

- remaining mapping lifetime
- upstream AAAA TTL when present
- any explicit TTL clamp introduced by configuration

If an implementation cannot preserve this relationship, it must shorten TTLs
rather than overstate freshness.

## Backend Artifact Contract

The backend-neutral artifact is part of the public contract.

Version `v1` preserves a shape like:

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

The artifact is the source contract the adapter consumes.

Tayga-specific rendering must remain downstream of this artifact rather than
becoming the public architecture.

## Apply / Reload Contract

The control plane owns:

- artifact generation
- persistence of mapping state
- coordination of backend apply/reload

Preserved expectations for `v1`:

- the daemon must not treat in-memory state alone as authoritative
- mapping removal must imply safe backend update/reload semantics
- failed artifact generation blocks publication of new synthesized answers
- failed backend apply/load makes translation-dependent synthesis unavailable

This preserves a fail-closed model instead of allowing silent drift between
resolver and backend state.

## Status and Degraded-State Contract

The control plane must expose machine-readable status.

Version `v1` preserves a status surface with at least:

- contract/status version
- overall state such as `active`, `inactive`, or `degraded`
- backend health
- mapping counts and/or mapping stats
- boundary flags for unsupported HA/multi-WAN assumptions
- reasons when synthesis or backend application is unavailable

The first slice should keep exposing:

- a persisted mapping file under `/var/lib/router-clat/`
- a rendered backend artifact under `/run/router-clat/`
- a status summary under `/run/router-clat/status.json`

## Failure Contract

The first slice prefers fail-closed and loud behavior.

Preserved failure expectations:

- if the control plane cannot render a backend artifact, it must not publish new
  synthesized answers
- if the backend cannot load the current artifact, the control plane must treat
  translation-dependent synthesis as unavailable
- if the state directory is unreadable or corrupt, startup should fail loudly
  rather than silently dropping state
- if the upstream IPv6 path disappears, existing state may remain inspectable,
  but new synthesis should fail rather than claiming working reachability
- if topology assertions fail after configuration changes, the unit should fail
  explicitly

## Adapter Capability Boundary

Tayga is behind an adapter boundary.

The public contract does not promise Tayga forever. It only promises that any
adapter must preserve:

- mapping/state semantics
- artifact semantics
- fail-closed behavior
- status/degraded-state reporting

Reasons the adapter may change later include:

- insufficient mapping telemetry
- unsafe reload behavior
- performance limits
- HA or ownership needs beyond the current Tayga-shaped first slice

## Versioning Rule

This note is versioned as contract `v1`.

Future extracted repos or alternate implementations should consume the contract
by version rather than guessing from implementation details.

Any breaking change to:

- persisted mapping record shape
- artifact schema
- DNS answer semantics
- failure behavior
- status fields required for operators/tests

should be treated as a contract-version discussion, not as a quiet refactor.

## Relationship To The Existing Design Note

[`docs/DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md) remains the broader design
and rationale document.

This file is narrower:

- it freezes the preserved public control-plane behavior
- it identifies what later preservation tests should target
- and it keeps Tayga and the current Python daemon from accidentally becoming
  the public API
