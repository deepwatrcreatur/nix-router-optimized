# 59 - Dashboard Service Control Auth and Boundary

## Status: `ready`

## Objective

Turn the long-deferred dashboard service-control idea into an explicit,
supportable read/write slice by adding:

- an authentication boundary
- a bounded service-action surface
- and honest operator guidance about what the dashboard may mutate

without collapsing the inventory/status dashboard into a general-purpose remote
shell.

## Rationale

The dashboard already exposes useful read-only operational surfaces, and the
docs explicitly defer service control until authentication exists.

That is the right boundary so far, but it leaves an awkward product gap:

- the UI suggests an obvious next step
- the API already has service-status visibility
- but there is no declared or documented write path at all

This item exists to settle that boundary deliberately rather than letting
ad hoc POST endpoints become the real authority.

## Requirements

- [ ] Define the first bounded service-control scope, including:
      - which actions are allowed (`start` / `stop` / `restart` or narrower)
      - which services are eligible
      - which services remain read-only
- [ ] Add an authentication and authorization model appropriate for the local
      router dashboard surface rather than leaving write endpoints unauthenticated
- [ ] Make the mutation boundary explicit in both code and docs so operators can
      tell which dashboard surfaces are read-only vs write-capable
- [ ] Add backend/API guardrails so unsupported services or actions fail clearly
      instead of silently widening privileges
- [ ] Keep the feature intentionally small; do not turn the dashboard into a
      generic command runner

## Verification

- [ ] A user cannot trigger service actions without the intended auth path
- [ ] An authenticated operator can perform the supported service action set on
      the supported service list
- [ ] Unsupported actions and services fail explicitly
- [ ] Docs clearly describe the mutation boundary and support stance

## Notes

This item is about **bounded authenticated service control**.

It should not expand into:

- arbitrary shell command execution
- broad configuration editing
- or a full role-based admin framework unless the bounded slice proves too small
