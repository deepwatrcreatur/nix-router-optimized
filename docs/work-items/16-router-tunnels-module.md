# Router Tunnels Module

Status: done

Branch: `feat/router-tunnels-module`

## Goal

Introduce a `services.router-tunnels` NixOS module that models application tunnels
(e.g., zrok, ngrok) as declarative metadata feeding the router dashboard, without
owning tunnel lifecycle management.

## Scope

- Define `services.router-tunnels` options for a list of tunnel entries.
- Each tunnel captures provider (zrok/ngrok/other), name, systemd unit, optional
  public URL, and description.
- Ensure the module is safe to import unconditionally and composes with
  existing router-* modules.

## Acceptance Criteria

- A new `router-tunnels` module is exported from the flake and can be enabled in
  NixOS configurations.
- Configurations using `services.router-tunnels.tunnels` evaluate successfully.
- No systemd units or extra services are introduced by this module; it remains
  metadata-only.
