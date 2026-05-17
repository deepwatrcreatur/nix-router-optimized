---
name: router-module-eval-and-smoke-loop
description: Choose the narrowest existing nix-router-optimized eval and smoke checks for router module, doc example, and flake export changes. Validation only; do not deploy, rebuild, or mutate live routers.
when_to_use: Use when changing modules/, tests/, flake.nix, README.md, or docs examples in this repo. Prefer targeted .#checks.<system>.* builds over a full nix flake check unless the change is broad and cross-cutting.
---

# Router module eval and smoke loop

Use this skill to pick and run the smallest existing check set that matches the
part of the router flake you changed.

This skill is intentionally read-only and validation-focused.

## Hard boundaries

Allowed:
- inspect changed files and existing checks
- run read-only `nix build -L .#checks.<system>.<check-name>` commands
- report which checks passed, failed, or were already failing for unrelated reasons

Do not:
- run `nixos-rebuild`, `deploy-rs`, or any live deployment workflow
- SSH into routers or mutate remote systems
- restart services, reload firewall state, or apply runtime config
- expand to `nix flake check` by default when a narrower check family exists

## Command pattern

Prefer a concrete check build:

```bash
system=$(nix eval --impure --raw --expr builtins.currentSystem 2>/dev/null || echo x86_64-linux)
nix build -L .#checks.${system}.<check-name>
```

Run the smallest useful set first. Only widen if the diff crosses multiple
check families or if `flake.nix` / `tests/default.nix` changed in a way that
re-wires several exported checks.

## Selection loop

1. Read the diff and list the touched modules, docs, and exported flake surfaces.
2. Start with per-module import evals for changed exported modules.
3. Add the smallest family-specific smoke/eval checks that cover the behavior you changed.
4. Add doc/example checks only when the diff changes README or docs examples, or changes module behavior those examples depend on.
5. Stop once the targeted checks for every touched area have run.
6. Only consider a broader sweep after targeted checks if the change is genuinely cross-cutting.

## Core exported-surface checks

Use these when the change affects flake exports, module wiring, or default bundle
composition.

- `module-<module-name>-import-eval`
  - First check for any changed exported module under `modules/`.
  - Example: `modules/router-firewall.nix` -> `module-router-firewall-import-eval`
- `exported-module-list-eval`
  - Add when changing `flake.nix`, `self.nixosModules`, module export names, or anything that could remove/rename an exported module.
- `default-module-bundle-eval`
  - Add when changing `self.nixosModules.default` composition or broad module interactions expected from the default bundle.

## Area-to-check mapping

| Touched area | Start with | Add when relevant |
| --- | --- | --- |
| Any exported module in `modules/router-*.nix` | `module-<name>-import-eval` | Family-specific checks below |
| `flake.nix`, `tests/default.nix`, module export list, default bundle composition | `exported-module-list-eval` | `default-module-bundle-eval`, plus import evals for changed modules |
| README quick start or default bundle docs | `readme-quick-start-router-eval` | `readme-default-bundle-router-eval` |
| `docs/*.md` or README examples | Matching `docs-*-example-eval` or README doc check | Related module import evals if module behavior changed too |
| `modules/router-firewall.nix`, `modules/router-optimizations.nix`, interface derivation, route-to-WAN logic | `router-firewall-derives-interfaces-eval`, `router-firewall-extra-trusted-only-eval` | `router-wireguard-route-to-derived-wan-eval`, `router-openvpn-route-to-derived-wan-eval`, and relevant VPN smoke checks |
| VPN and overlay modules | Relevant `router-*-eval` entries from `vpn-smoke.nix` | Dashboard metadata evals when dashboard/tunnel metadata changes |
| `modules/router-kea.nix` and DHCP/DNS interactions | `router-kea-search-domains-eval` | `router-kea-invalid-network-address-pool-fails` |
| `modules/router-nptv6.nix` | `router-nptv6-eval` | `module-router-nptv6-import-eval`, firewall import eval if rules are integrated there |
| PvD support in `modules/router-networking.nix` | `router-pvd-eval` | `module-router-networking-import-eval` |

## Doc/examples eval coverage

Use the matching doc example check when changing the corresponding example text,
or when changing module behavior that those examples are meant to prove.

Common examples wired in `tests/doc-examples.nix` include:
- `readme-quick-start-router-eval`
- `readme-default-bundle-router-eval`
- `readme-common-wan-policy-eval`
- `docs-router-dhcp-pxe-example-eval`
- `docs-router-tailscale-example-eval`
- `docs-router-headscale-example-eval`
- `docs-router-openvpn-example-eval`
- `docs-router-netbird-example-eval`
- `docs-router-zerotier-example-eval`
- `docs-overlay-vpn-dual-example-eval`
- `docs-router-wireguard-example-eval`
- `docs-router-security-hardened-example-eval`
- `docs-router-zones-example-eval`
- `docs-router-firewall-counters-eval`
- `docs-router-dashboard-remote-access-example-eval`

Rule of thumb: if the diff changes a documented example, run that example check.
If the diff changes the module that backs a documented example, run the matching
doc example check as a regression guard.

## Interface and firewall invariants

Reach for these when interface role derivation or firewall-rendered rules change:

- `router-firewall-derives-interfaces-eval`
- `router-firewall-extra-trusted-only-eval`
- `router-wireguard-route-to-derived-wan-eval`
- `router-openvpn-route-to-derived-wan-eval`
- failure checks such as `router-openvpn-route-to-wan-no-wan-fails-eval` when assertions around missing WAN inputs are part of the change

These are especially relevant for changes in:
- `modules/router-firewall.nix`
- `modules/router-optimizations.nix`
- VPN modules that inject trusted, overlay, or route-to-WAN rules

## VPN smoke checks

Use `tests/vpn-smoke.nix` for VPN, overlay, tunnel, and dashboard metadata work.
Pick the checks that match the touched module.

Examples:
- WireGuard: `router-wireguard-minimal-eval`, `router-wireguard-route-to-wan-eval`, `router-wireguard-route-to-wan-no-wan-fails-eval`
- OpenVPN: `router-openvpn-single-wan-eval`, `router-openvpn-multiple-instances-eval`, `router-openvpn-route-to-derived-wan-eval`, `router-openvpn-route-to-wan-no-wan-fails-eval`
- Tailscale: `router-tailscale-with-firewall-eval`, `router-tailscale-without-firewall-eval`
- Headscale: `router-headscale-standalone-eval`, `router-headscale-with-caddy-eval`, `router-headscale-with-tailscale-eval`
- Netbird: `router-netbird-with-firewall-eval`, `router-netbird-without-firewall-eval`, `router-netbird-dual-overlay-eval`, `router-netbird-port-collision-fails-eval`, `router-netbird-dns-and-login-eval`
- Zerotier: `router-zerotier-with-firewall-eval`, `router-zerotier-without-firewall-eval`
- Cloudflare Tunnel / dashboard tunnel metadata: `router-cloudflare-tunnel-wrapper-eval`, `router-cloudflare-tunnel-wildcard-url-eval`, `router-dashboard-tunnels-metadata-eval`, `router-dashboard-tunnels-disabled-metadata-eval`, `router-dashboard-remote-admin-metadata-eval`, `router-dashboard-remote-admin-disabled-metadata-eval`, `router-dashboard-vpn-metadata-eval`

## Kea eval checks

Use these for `modules/router-kea.nix` and for changes that affect DHCP option
rendering through `router-networking` or `router-dns-service` integration.

- `router-kea-search-domains-eval`
- `router-kea-invalid-network-address-pool-fails`

## NPTv6 and PvD checks

Use these when touching IPv6 translation or provisioning-domain logic.

- `router-nptv6-eval`
  - for `modules/router-nptv6.nix` and related firewall NAT integration
- `router-pvd-eval`
  - for `modules/router-networking.nix` changes that affect `pvds`, RA, or rendered systemd-networkd PvD config

## Adjacent pro-feature checks

If the diff is in these modules, prefer the existing targeted checks instead of a
broad sweep:

- NAT64: `router-nat64-eval`
- DNS64: `router-dns64-eval`
- SQM: `router-sqm-eval`
- mDNS reflector: `router-mdns-eval`
- UPnP: `router-upnp-eval`
- BGP: `router-bgp-eval`
- HA DNS composition: `router-ha-dns-unbound-eval`, `router-ha-dns-technitium-eval`, `router-ha-dns-technitium-ipv6-eval`

## When to widen beyond the first targeted checks

Widen only when one of these is true:
- the diff touches more than one check family
- `flake.nix` or `tests/default.nix` changes the exported check graph
- the change alters shared plumbing used by many modules
- a targeted failure suggests a second family is tightly coupled to the changed code

If several families are touched, run the union of those families first. Do not
jump straight to `nix flake check` unless the change is broad enough that the
narrow families no longer describe the risk.

## Stop conditions

Stop when all of the following are true:
- each touched area has at least one matching targeted check run
- import evals for changed exported modules have run
- any relevant failure check has been exercised when the diff changes an assertion boundary
- results are summarized with passed checks, failed checks, and any clearly unrelated pre-existing failures

If an unrelated pre-existing check failure blocks a broader sweep, report it and
stop after confirming the targeted checks for your touched area are still the
right ones.

## Two concrete selection examples

### Example A: firewall plus WireGuard route-to-WAN change

If the diff touches `modules/router-firewall.nix` and `modules/router-wireguard.nix`, start with:
- `module-router-firewall-import-eval`
- `module-router-wireguard-import-eval`
- `router-firewall-derives-interfaces-eval`
- `router-firewall-extra-trusted-only-eval`
- `router-wireguard-route-to-wan-eval`
- `router-wireguard-route-to-derived-wan-eval`
- `router-wireguard-route-to-wan-no-wan-fails-eval`

Only add broader VPN or doc checks if the diff also changes those surfaces.

### Example B: PvD or NPTv6 change

If the diff touches `modules/router-networking.nix` PvD logic, start with:
- `module-router-networking-import-eval`
- `router-pvd-eval`

If the diff touches `modules/router-nptv6.nix`, start with:
- `module-router-nptv6-import-eval`
- `router-nptv6-eval`
- `module-router-firewall-import-eval` if firewall integration changed too

These are targeted regression checks; they are not live router operations.
