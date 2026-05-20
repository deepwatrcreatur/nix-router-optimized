# 39 - Router CLAT Post-Landing Cleanup and Boundary Surfacing

## Status: `done`

## Objective

After the first-slice `router-clat` landing, align the repo's user-facing docs,
status surfaces, and enable-time messaging with what actually exists today:

- a meaningful declarative contract and assertion layer
- but not yet a complete runtime translation feature

## Rationale

Discussion 10 concluded that the project made the right call by landing a
bounded declarative first slice before attempting a runtime translator.

However, the merge also left an honesty gap:

- `router-clat` now exists in the option tree and flake exports
- but it is not clearly surfaced in the top-level README or status docs
- and the current enable path does not loudly remind operators that this remains
  experimental and contract-oriented rather than runtime-complete

This cleanup item exists to close that gap before the repo moves on to any
runtime-oriented CLAT work.

## Requirements

- [x] Add `router-clat` to the top-level `README.md` with wording that is
      explicit about its current maturity:
      - experimental
      - first-slice / contract-oriented
      - not yet a full runtime translation story
- [x] Surface `router-clat` in the most relevant status doc(s), with a clear
      maturity description rather than implying general availability
- [x] Add enable-time warning language or equivalent boundary signaling in
      `modules/router-clat.nix` so users are reminded that:
      - the current slice is bounded
      - runtime translation is not yet fully realized
      - HA/active-owner assumptions are still narrow
- [x] Tighten the docs around the provisional naming boundary so contributors do
      not forget that `router-clat` became load-bearing in the option tree before
      stabilization was fully settled
- [x] Add at least one explicit note about current HA/non-HA expectations so
      operators do not infer a failover story that the module does not yet claim

## Verification

- [x] A user scanning `README.md` can tell that `router-clat` exists
- [x] That same user can also tell that it is **not yet** a normal mature
      operator-facing feature
- [x] Enabling `services.router-clat.enable = true;` no longer relies on the user
      reading deep design docs to understand that the current slice is
      experimental and incomplete
- [x] The repo's status/doc surfaces do not overclaim CLAT maturity

## Notes

This item is intentionally **cleanup and boundary-surfacing only**.

It should not be expanded into:

- a Tayga/runtime implementation item
- a DNS synthesis implementation item
- or a live observability/runtime validation item

Those belong to later work once the repo has cleaned up how the current slice is
presented and bounded.
