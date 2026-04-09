# 09 PXE Review Follow-Up Hardening

Status: `ready`

Suggested branch: `fix/router-pxe-review-followups`

## Goal

Resolve the concrete PR review follow-ups on the PXE work before merging it to
`main`.

## Why This Matters

The first PXE PR is close, but review feedback identified likely correctness
risks that should be checked directly rather than waived away:

- the new DHCP PXE option path may have an evaluation edge case around default
  attribute handling
- Technitium reservation sync should use normalized MAC addresses consistently
  so writes and comparisons do not drift across formats

These are small enough for one cleanup PR and important enough to settle before
the PXE feature becomes the new baseline.

## Scope

- verify the DHCP module review finding against the current code and fix it if
  it is real
- verify the Technitium MAC-normalization finding against the current code and
  fix it if needed
- add the smallest useful validation or example coverage for the corrected
  behavior
- keep the PR focused on merge readiness for the existing PXE work

## Non-Goals

- expanding the PXE feature beyond the current first slice
- bundling unrelated DHCP or Technitium redesign
- reopening the already-decided PXE architecture split

## Validation

- `nix flake check --no-build` still passes
- the PXE example eval path still produces the expected DHCP boot fields
- any normalization-sensitive Technitium path behaves consistently with mixed
  MAC input formats
