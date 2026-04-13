# Dashboard Blue Theme

Status: ready

Branch: `feat/dashboard-blue-theme`

## Goal

Rework the dashboard visual language toward the blue, compact, security-console
look requested by the operator, using MikroDash as a rough reference while
preserving this repo's existing widget model.

## Scope

- Shift the dashboard from the current orange-accent PegaProx theme to a blue
  network-operations theme.
- Improve card density, spacing, borders, shadows, and typography so the UI
  feels less busy and more organized.
- Style the new tab shell with strong active states and clear page hierarchy.
- Keep the UI usable on mobile widths.

## Acceptance Criteria

- The primary accent color is blue/cyan rather than orange.
- Widgets remain legible and accessible in the dark theme.
- The page background has intentional depth without obscuring data.
- The existing widget markup does not need large per-widget rewrites.
