# Work Item 104: Upstream File-Backed Grafana Secret Key for NixOS 26.05+ Compatibility

**Status:** ready  
**Priority:** P2 (Medium)  
**Created:** 2026-09-19  

## Description

Update `modules/monitoring.nix` to use file-backed Grafana secret key storage (`$__file{...}`) instead of a static plaintext string, ensuring compatibility with modern NixOS releases where plaintext defaults are deprecated or removed.

## Context & Rationale

In NixOS 26.05+, `services.grafana` removed the built-in fallback default secret key. In `modules/monitoring.nix`, line 551 currently specifies:
```nix
secret_key = lib.mkDefault "SW2YcwTIb9zpOOhoPsMm";
```
This triggers evaluation warnings or configuration conflicts in downstream modern systems. Downstream production configs had to force:
```nix
environment.etc."grafana/secret_key".text = "SW2YcwTIb9zpOOhoPsMm";
services.grafana.settings.security.secret_key = lib.mkForce "$__file{/etc/grafana/secret_key}";
```

## Objectives

1. In `modules/monitoring.nix`, provide an automated file-backed secret key mechanism or generate `/etc/grafana/secret_key` with secure permissions.
2. Point `services.grafana.settings.security.secret_key` to the file-backed source via `$__file{...}`.
3. Allow user override through a declarative option.

## Acceptance Criteria

- [ ] Grafana starts without evaluation warnings or secret key format errors on NixOS 25.11 and 26.05+.
