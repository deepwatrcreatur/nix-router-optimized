# Router Remote Admin Module

Status: pending

Branch: `feat/router-remote-admin-module`

## Goal

Introduce a `services.router-remote-admin` NixOS module that models remote administration entry points (e.g., Guacamole, MeshCentral, SSH bastions) as declarative metadata consumed by the router dashboard, without owning service lifecycle management.

## Scope

- Define `services.router-remote-admin` options for a list of remote access entries.
- Each entry captures type (guacamole/meshcentral/ssh/other), name, systemd unit, URL, and description.
- Ensure the module is safe to import unconditionally and composes with existing router-* modules.

## Acceptance Criteria

- A new `router-remote-admin` module is exported from the flake and can be enabled in NixOS configurations.
- Configurations using `services.router-remote-admin.entries` evaluate successfully.
- No systemd units or extra services are introduced; the module remains metadata-only.
