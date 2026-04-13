# Dashboard Tabs Shell

Status: done

Branch: `feat/dashboard-tabs-shell`

## Goal

Replace the current one-page dashboard surface with a tabbed page shell so
widgets can be organized by task instead of all competing for space on the
homepage.

## Scope

- Add top-level dashboard tabs for overview, network, services, security, and
  VPN.
- Move existing widgets into page-specific GridStack containers.
- Preserve layout persistence per page instead of one global GridStack layout.
- Keep the VPN page structurally present, with detailed VPN status landing in a
  follow-up PR.

## Acceptance Criteria

- Existing widgets still render and refresh.
- Switching tabs does not destroy widget polling state.
- Reset layout clears the active tabbed layout state.
- The shell works without GridStack loaded by falling back to static grids.
- No backend behavior changes are required for this item.
