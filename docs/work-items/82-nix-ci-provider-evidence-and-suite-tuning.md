# 82 - Nix CI Provider Evidence And Suite Tuning

## Status: `in-progress`

## Objective

Capture real provider-side evidence for the coarse CI suite transition and tune
the suite split only if the current `6`-suite boundary proves too coarse or too
cosmetic on `nix-ci.com`.

Suggested branch: `docs/router-nix-ci-provider-evidence`

## Rationale

Item `79` closed the local before/after baseline honestly:

- visible exported job count clearly dropped
- local narrow-leaf debugging still works
- exact provider-side worker-second savings were **not** proven

That means the repo now has a coherent local story, but still lacks the last
piece of evidence:

- whether the six exported suites materially improved provider behavior, or
  mainly cleaned up UI/status clutter

This item exists so the repo does not confuse “better shaped CI” with “proven
cheaper CI.”

## Requirements

- [ ] Capture a real provider-side before/after comparison from `nix-ci.com` or
      the repo’s equivalent CI surface
- [ ] Record at least:
      - visible job count
      - wall-clock timing
      - any available worker-second / billed-cost signal
      - one example of failure-debugging ergonomics under the suite model
- [ ] Decide whether the current `6`-suite shape is still the right default
- [ ] If the current split is too coarse, recommend a narrower suite breakdown
      based on actual evidence rather than taste
- [ ] Update [`docs/router-nix-ci-baseline.md`](../router-nix-ci-baseline.md)
      with the provider-side evidence and conclusion

## Verification

- [ ] Future maintainers can tell whether the suite transition was:
      - mostly cosmetic
      - economically real
      - or mixed
- [ ] Any proposed suite split change is grounded in observed provider behavior
      instead of guesswork

## Notes

This item is about **provider evidence and suite tuning after the boundary
change**.

It should not reopen the basic decision to keep fine-grained local leaves unless
the provider evidence shows the current split is actively harmful.
