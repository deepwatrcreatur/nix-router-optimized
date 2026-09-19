# Work Item 100: Upstream Router Pangolin Service Hardening & Port Configuration

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-19  

## Description

Upstream the critical runtime fixes for `services.router-pangolin` from downstream deployments to resolve crash-restart loops and port collisions with other router services.

## Context & Rationale

In standalone deployments, `services.router-pangolin` exhibits multiple fatal startup issues:
1. Upstream nixpkgs `services.pangolin` applies systemd `SocketBindDeny = [ "ipv4:tcp" "ipv4:udp" "ipv6:udp" ]`, which prevents the Node.js process from binding listening TCP ports on `127.0.0.1` (crashing immediately on startup).
2. Pangolin default `internal_port` is 3001, colliding directly with Grafana (`http_port = 3001`) when both monitoring and reverse proxy services are enabled on the same router node.
3. The packaged `server.mjs` synchronously reads database definitions from `server/db/*.json` (`names.json`, `ios_models.json`, `mac_models.json`), but these reside in `${package}/share/pangolin/dist/*.json` and must be symlinked into the runtime state directory.
4. During service initialization, `cp -rd .../share/pangolin/.next .` copies `.next` with read-only permissions (`0555`). Subsequent restarts attempt cleanup without `.nix_skip_setup` and fail with permission denied errors.
5. If `/etc/pangolin/pangolin.env` is missing, startup fails validation requiring a server secret.
6. Internal WebUI / API ports (3000 and 3002) are not automatically opened in `router-firewall` when `openFirewall = true`.

## Objectives

1. In `modules/router-pangolin.nix`, loosen `systemd.services.pangolin.serviceConfig.SocketBindDeny` to `[ "ipv4:udp" "ipv6:udp" ]` so localhost TCP can be bound.
2. Change the default `internal_port` from 3001 to 3005 (or make it a first-class configurable option with default 3005) to avoid colliding with Grafana.
3. Add a robust `preStart` script to:
   - Auto-provision `/etc/pangolin/pangolin.env` with a secure random `SERVER_SECRET` if not present.
   - Symlink `${package}/share/pangolin/dist/*.json` into `/var/lib/pangolin/server/db/`.
   - Ensure `.next` has write permissions (`chmod -R u+rwX`) and touch `/var/lib/pangolin/.next/.nix_skip_setup`.
4. When `services.router-firewall` is enabled and `openFirewall = true`, open trusted TCP ports 3000 and 3002 in `services.router-firewall.trustedTcpPorts`.

## Acceptance Criteria

- [ ] `pangolin.service` starts and reaches `active (running)` without continuous crash loops.
- [ ] No port collision occurs with `services.grafana` on port 3001.
- [ ] NixOS evaluation tests in `tests/` pass cleanly.
