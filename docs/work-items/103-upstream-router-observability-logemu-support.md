# Work Item 103: Upstream Ulogd LOGEMU Output Support in Router Observability

**Status:** ready  
**Priority:** P1 (High)  
**Created:** 2026-09-19  

## Description

Add support for the standard `LOGEMU` output plugin in `modules/router-observability.nix` so that `services.ulogd` starts reliably on systems using vanilla `pkgs.ulogd` without crashing on missing JSON plugins.

## Context & Rationale

`modules/router-observability.nix` currently hardcodes:
```nix
plugin = [
  "${pkgs.ulogd}/lib/ulogd/ulogd_inppkt_NFLOG.so"
  "${pkgs.ulogd}/lib/ulogd/ulogd_raw2packet_BASE.so"
  "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IFINDEX.so"
  "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IP2STR.so"
  "${pkgs.ulogd}/lib/ulogd/ulogd_filter_PRINTPKT.so"
  "${pkgs.ulogd}/lib/ulogd/ulogd_output_JSON.so"
];
stack = "log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,json1:JSON";
```
However, `ulogd_output_JSON.so` is not included in standard `pkgs.ulogd` in Nixpkgs; it requires a custom build overlay (`jansson` support). Systems consuming `nix-router-optimized` without this exact overlay fail during activation with:
- `can't find requested plugin JSON`
- `not even a single working plugin stack`
Furthermore, `ulogd` 2.0.9 rejects `global.loglevel` in configuration files.

## Objectives

1. In `modules/router-observability.nix`, add an option `services.router-observability.ulogdOutputPlugin = mkOption { type = types.enum [ "logemu" "json" ]; default = "logemu"; ... };`.
2. Configure the plugin list and stack dynamically:
   - When `"logemu"`, use `ulogd_output_LOGEMU.so` and stack `log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU` outputting to `/var/log/ulogd/flow.log`.
   - When `"json"`, use `ulogd_output_JSON.so` outputting to `/var/log/ulogd/flow.json`.
3. Remove invalid `loglevel` directives from the generated configuration.

## Acceptance Criteria

- [ ] Vanilla NixOS evaluation and system build with `ulogdOutputPlugin = "logemu"` succeeds out of the box.
- [ ] `ulogd.service` starts cleanly and writes netfilter flow logs to `/var/log/ulogd/flow.log`.
