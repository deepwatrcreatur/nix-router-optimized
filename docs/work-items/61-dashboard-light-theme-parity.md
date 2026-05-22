# 61 - Dashboard Light Theme Parity

## Status: `ready`

## Objective

Make `services.router-dashboard.theme = "light"` a real supported surface
rather than a nominal option backed only by dark-theme styling assumptions.

The first slice should bring the light theme to clear functional and visual
parity for the existing dashboard pages and widgets.

## Rationale

The dashboard module already exposes a `theme` option with `dark` and `light`
values, but the current implementation status still calls out the light theme
as not yet implemented.

That creates a support-boundary mismatch:

- the option surface implies a working choice
- but the styling and validation story still appear dark-theme-first

This item exists to close that gap before more dashboard slices accumulate on a
theme contract that is only half-real.

## Requirements

- [ ] Implement the actual light-theme styling path for the current dashboard
      shell and widgets rather than only keeping placeholder variables
- [ ] Verify readable contrast, status colors, cards, tables, and charts in the
      light theme across the currently shipped widget set
- [ ] Ensure the inventory browser and other recently added pages inherit the
      light theme cleanly rather than relying on dark-only assumptions
- [ ] Update docs or examples so operators can tell the light theme is now
      supported, if that is the resulting stance

## Verification

- [ ] Setting `services.router-dashboard.theme = "light";` produces a legible,
      coherent dashboard for the currently supported pages
- [ ] No widget becomes unreadable or visually broken when switching themes
- [ ] The implementation status docs no longer describe the light theme as
      unimplemented

## Notes

This item is about **theme parity for the existing dashboard**, not a broad
design rewrite or theme system expansion.
