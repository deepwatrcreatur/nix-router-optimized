# 58 - Router CLAT Elixir Extraction and Release Boundary

## Status: `ready`

## Objective

Make the repo-split decision for an Elixir `router-clat` control plane
explicitly and evidence-first, rather than letting extraction happen implicitly
because an alternate implementation exists.

## Rationale

Round 126 produced a real disagreement:

- some voices wanted a separate Elixir repo immediately
- others wanted extraction only after parity and contract stability

That disagreement is important enough to preserve in the queue instead of being
smuggled into implementation.

This item exists to decide, with evidence in hand, whether extraction improves
maintainability enough to justify:

- versioning and release overhead
- cross-repo compatibility management
- additional packaging work
- operator/support complexity

## Requirements

- [ ] Evaluate whether the Elixir path has reached enough contract stability and
      preservation-test confidence to justify extraction
- [ ] Define the release boundary if extraction is chosen, including:
      - versioning strategy
      - artifact/release packaging
      - compatibility contract between repos
      - ownership of integration tests
- [ ] Define the non-extraction rationale if the project decides the Elixir path
      should remain in-repo for the foreseeable future
- [ ] Make the chosen boundary explicit in docs so contributors do not infer that
      repo layout is undecided by accident

## Verification

- [ ] The project has an explicit recorded decision on whether the Elixir path is
      extracted or remains in-repo
- [ ] If extracted, the release and compatibility boundary is clear enough to
      avoid guess-based cross-repo coupling
- [ ] If not extracted, the repo documents why the control plane remains local

## Notes

This item should follow:

- the control-plane contract work
- preservation tests
- and at least a bounded Elixir path proving whether the split is worth it
