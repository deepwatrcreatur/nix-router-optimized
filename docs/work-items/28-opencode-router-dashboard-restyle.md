# 28 — Router Dashboard OpenCode Restyle

## Status: `done` — **Codex** — `feat/opencode-dashboard-style`

## Objective

Restyle the router dashboard to follow the `opencode.ai` `DESIGN.md` system
from `VoltAgent/awesome-design-md`.

## Design Source

- `design-md/opencode.ai/DESIGN.md`

## Rationale

The current router dashboard uses a blue operations-console look. The OpenCode
design is a better fit for a technical, terminal-native control surface:

- monospaced-first typography
- warm cream / ink / near-black palette
- hairline borders with minimal ornament
- dark TUI-inspired focal surfaces

That language fits a read-mostly operations console without turning it into a
generic enterprise panel.

## Requirements

- [ ] Replace the current blue visual language in
      `modules/router-dashboard/css/dashboard.css`
- [ ] Update `modules/router-dashboard/index.html` chrome where needed to better
      match the OpenCode information hierarchy
- [ ] Preserve current dashboard structure, tabs, widgets, and API contracts
- [ ] Keep the result readable on desktop and mobile

## Verification

- [ ] Dashboard uses the OpenCode-inspired palette and typography
- [ ] Existing widget layout and navigation still work
- [ ] No widget/API behavior changes are required for the visual restyle

## Outcome

- Restyled the dashboard chrome and widget surfaces to a cream / ink
  OpenCode-inspired console theme.
- Updated the shell copy and hierarchy in `index.html` without changing the
  dashboard tab structure or API contracts.
- Kept the work CSS-only plus light HTML copy changes so the router dashboard
  behavior stays intact.
