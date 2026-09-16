# Work Item 97: `routerctl` CLI Diagnostics & Static Firewall Explainer

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-16  

## Description

Refactor `pkgs/router-diag` into a structured, modular `routerctl` diagnostic CLI with JSON output (`--json`), and implement `routerctl firewall explain` backed by an evaluated declarative policy manifest (`/etc/router/policy-manifest.json`).

## Context & Rationale (From Discussion 20)

The current diagnostic script `pkgs/router-diag/router-diag.sh` is an informal 120-line bash script with ANSI terminal formatting and no machine-readable output. In complex setups with multiple zones and flowtable offloading, operators have no fast way to determine why packets are dropped or permitted without parsing raw `nft list ruleset`. A structured `routerctl` CLI enables SSH automation, Prometheus metrics generation, and instant policy explainability.

## Objectives

1. Refactor `pkgs/router-diag` into `routerctl` with subcommands: `status`, `health`, `interfaces`, `firewall`, `diagnostics`.
2. Ensure every subcommand supports `--json` schema output alongside human-friendly table format.
3. Export compile-time zone forwarding relationships from `services.router-zones` to `/etc/router/policy-manifest.json`.
4. Implement `routerctl firewall explain --src-iface <iface> --dst-iface <iface> --proto <proto> --dport <port>`:
   - Resolves interfaces to source/destination zones.
   - Evaluates policy manifest to print decision (`ALLOW` / `DROP`), matching rule, and corresponding nftables chain.
5. Provide `routerctl firewall trace` using ephemeral `nftrace` hooks for live packet path analysis.

## Acceptance Criteria

- [ ] `routerctl status --json` and `routerctl health --json` output valid, machine-parseable JSON.
- [ ] `/etc/router/policy-manifest.json` exported deterministically at build time.
- [ ] `routerctl firewall explain` successfully prints zone mappings and policy resolution without generating network traffic.
- [ ] Backwards-compatible `router-diag` symlink retained.
