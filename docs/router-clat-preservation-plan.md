# router-clat Preservation Fixtures and Parity Plan

## Status

Preservation plan version: `v1`

This note defines the named behavior set that future `router-clat`
implementations must preserve. It complements the frozen public contract in:

- [`docs/router-clat-control-plane-contract.md`](./router-clat-control-plane-contract.md)

The goal is to let the repo compare the current Python control plane and a
future Elixir control plane against the same black-box cases instead of
assuming that a rewrite is correct because it "looks equivalent."

## Preserved Behavior Set

The current preserved `v1` behavior set is:

- `dns-aaaa-only-synthesis`
  - AAAA-only upstream answers synthesize an A answer from the local mapping
    pool.
- `mapping-reuse-and-deterministic-selection`
  - an existing mapping is reused when possible, otherwise multiple AAAA
    answers are sorted and the first address is chosen deterministically.
- `mapping-persistence-across-restart`
  - durable mapping state survives control-plane restart when the persisted
    state is still fresh.
- `mapping-ttl-and-gc`
  - expired mappings are removed, the IPv4 address becomes reusable, and the
    rendered artifact reflects the removal.
- `status-degraded-when-backend-unhealthy`
  - the status surface reports `degraded` when translation-dependent synthesis
    cannot be honored safely.
- `artifact-schema-v1`
  - the backend-facing artifact stays backend-neutral and versioned.
- `status-schema-v1`
  - the status surface stays machine-readable and preserves boundary flags.

## Fixture Model

The initial fixtures live under:

- [`modules/router-clat/fixtures`](../modules/router-clat/fixtures)

Each fixture is intentionally backend-neutral. It describes one of:

- a preserved semantic case
- a public artifact/schema expectation
- a status/schema expectation

The fixture set is designed so a future Python or Elixir harness can evaluate
the same files without importing Tayga-specific assumptions.

## Current Harness Shape

The current parity harness is:

- [`modules/router-clat/test_preservation_fixtures.py`](../modules/router-clat/test_preservation_fixtures.py)

It does three things:

1. validates the generic public artifact/status shapes against named fixtures
2. exercises the current Python control plane and checks that its outputs
   satisfy those fixtures
3. validates a fake non-Tayga backend status fixture so the preservation suite
   does not silently encode Tayga as the only legal architecture
4. allows a bounded Elixir preview path to consume the same fixtures without
   silently becoming the default control plane

That last point matters. The repo currently ships Tayga as the first data-plane
backend, but the preservation suite must remain about the public contract rather
than about the current adapter name.

## Existing Coverage Mapped To The Preservation Set

The Python unit suite in
[`modules/router-clat/test_clat_dns.py`](../modules/router-clat/test_clat_dns.py)
already covers most of the semantics that the parity plan wants to preserve:

- DNS synthesis classes
- deterministic multi-AAAA selection
- mapping reuse
- persistence across restart
- TTL clamping
- mapping GC
- artifact rendering
- degraded/inactive/active status states
- HA and multi-WAN boundary flags

The new fixture harness does not replace those tests. It gives them named
black-box cases that later implementations can be compared against.

## Whole-System Coverage Boundary

The repo does not yet have a dedicated `router-clat` NixOS VM test harness.
Today the integration surface is covered by:

- eval checks for module wiring and inspectable runtime paths
- Python unit tests for control-plane semantics

The next preservation step after this note is to add VM coverage for:

- service start
- `clat0` lifecycle
- persistent state surviving service restart
- `/run/router-clat/mappings.json` and `/run/router-clat/status.json`
- sane operator-visible health when the backend is unavailable

That VM work is intentionally separate from the contract/fixture work here. The
point of this item is to freeze and exercise the preserved behavior model first.
