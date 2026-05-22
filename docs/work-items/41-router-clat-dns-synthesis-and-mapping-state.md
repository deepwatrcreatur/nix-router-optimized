# 41 - Router CLAT DNS Synthesis and Mapping State

## Status: `done`

## Objective

Implement the control-plane slice that makes `router-clat` operationally useful:

- DNS behavior for legacy IPv4-only clients
- mapping allocation and persistence
- mapping TTL / GC behavior
- backend artifact generation from authoritative mapping state

This item should turn the already-declared CLAT contract into a real
translation-control plane while preserving the bounded first-slice support model.

## Rationale

The design and first-slice contract work already narrowed the key questions:

- what topology is supported
- what route conflicts should be rejected
- what pools and prefixes must not overlap
- what the runtime boundary should eventually own

What is still missing is the actual logic that answers:

- how A-like answers are synthesized from upstream IPv6 reachability
- how mappings are keyed, refreshed, expired, and persisted
- how the runtime backend receives deterministic mapping artifacts

Without this control-plane layer, the runtime/backend lifecycle from work item 40
would still not amount to an operator-meaningful CLAT feature.

## Requirements

- [x] Implement the first-slice DNS behavior in a way that matches the existing
      design contract for:
      - AAAA-only answers
      - A-only answers
      - dual-stack answers
      - NXDOMAIN / NODATA
- [x] Define and persist authoritative mapping records under module-owned state
      rather than in transient process memory only
- [x] Implement mapping refresh and expiry semantics that match the declared
      `mappingTtl` / `gcInterval` contract
- [x] Render backend-facing mapping/config artifacts deterministically from that
      authoritative mapping state
- [x] Keep the backend contract backend-agnostic in public semantics even if the
      first runtime target is specific
- [x] Add focused validation for:
      - mapping creation
      - mapping refresh
      - mapping expiry / GC
      - DNS synthesis behavior by answer class

## Verification

- [x] A supported legacy IPv4-only client path can be explained end-to-end from
      DNS request to rendered translation artifact
- [x] Mapping state survives process restarts in the declared persistent path
- [x] Mapping expiry behavior is deterministic and testable
- [x] DNS answer behavior matches the documented first-slice boundary
- [x] The control-plane layer does not silently bypass the current explicit
      topology and coexistence boundaries

## Notes

This item should stay first-slice in ambition.

Do not expand it into:

- HA failover semantics
- broad multi-WAN support
- final naming stabilization
- polished dashboard UX

Those are later concerns once the control-plane path is real.
