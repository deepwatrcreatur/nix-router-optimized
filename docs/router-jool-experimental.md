# Router Jool Experimental Boundary

Last updated: 2026-05-28

## Purpose

Record the bounded outcome of the repo's first Jool evaluation pass without
pretending that a router-grade Jool backend exists here today.

## Current Result

The repo now exposes an explicit experimental backend gate:

- `services.router-nat64.translationBackend.backend = "jool-experimental"`
- `services.router-clat.translationBackend.backend = "jool-experimental"`

Both paths require:

- `translationBackend.allowExperimentalJool = true`

Even with that acknowledgement, the configuration fails explicitly today.

## Why It Fails

Current `nixpkgs` evidence in this workspace shows:

- `jool-cli` exists
- a supported router-grade Jool runtime / kernel-module lifecycle is not wired
  here

That means the repo can honestly support:

- an explicit evaluation gate
- explicit non-support language
- recorded parity gaps

It cannot honestly claim:

- a supported NAT64 Jool replacement
- a supported CLAT Jool replacement
- parity with the current Tayga-backed lifecycle

## What Is Missing Before A Real Runtime Spike

At minimum, a future runtime-capable Jool spike would need:

- packaging for the required runtime pieces, not just `jool-cli`
- explicit kernel/module ownership and loading semantics
- a translation interface / dataplane ownership story
- firewall integration points equivalent to the current Tayga path
- status and health surfaces with operator-meaningful parity
- clear migration semantics from the current Tayga-backed default

## Repo Stance

The current repo stance is:

- Tayga remains the supported backend
- Jool remains an experimental evaluation topic
- choosing `jool-experimental` is a deliberate evidence gate, not a hidden
  fallback path

This keeps the support boundary honest while still preserving a concrete place
to continue Jool investigation later.
