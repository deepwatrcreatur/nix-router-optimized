# 79 - Nix CI Worker-Second Baseline and Regression Check

## Status: `ready`

## Objective

Measure whether the reduced exported CI surface in `nix-router-optimized`
actually improves `nix-ci.com` economics and operator experience, rather than
assuming that fewer visible jobs automatically means lower spend.

Suggested branch: `docs/router-nix-ci-cost-baseline`

## Rationale

Round 132 was explicit that there are two different claims:

- a smaller exported check surface clearly reduces UI/status clutter
- a smaller exported check surface may or may not reduce billed worker-seconds,
  depending on whether repeated eval/build/setup work also falls

This item exists so the project captures real before/after evidence instead of
relying on intuition or commit-count folklore.

## Requirements

- [ ] Capture the pre-change baseline for the current exported CI surface,
      including at least:
      - exported top-level check count
      - representative `nix-ci.com` job shape
      - any available worker-second or duration evidence
- [ ] After the suite reshaping lands, capture the same evidence again
- [ ] Compare:
      - visible job count
      - wall-clock behavior
      - failure attribution/debugging ergonomics
      - and worker-second or equivalent cost signals where available
- [ ] Document whether the main gain came from:
      - reduced UI/status clutter
      - reduced per-job overhead
      - reduced repeated evaluation/build work
      - or some mixture of the above
- [ ] If the new suite shape regresses debugging too far, recommend a narrower
      suite split instead of declaring victory too early

## Verification

- [ ] The repo has a durable before/after record rather than a vague claim that
      “CI got cheaper”
- [ ] Future maintainers can tell whether the suite reshaping was economically
      real, mostly cosmetic, or mixed
- [ ] Any next-step optimization work is grounded in observed bottlenecks instead
      of guesswork

## Notes

This item is about **evidence and regression checking after the CI boundary
change**.

It should not expand into a general CI-provider comparison or a move away from
repo-native Nix validation.
