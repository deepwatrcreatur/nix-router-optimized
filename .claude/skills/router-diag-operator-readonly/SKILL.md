---
name: router-diag-operator-readonly
description: Use router-diag for safe observational router checks only. Limit usage to read-only show commands and stop at reporting; do not remediate or mutate router state.
when_to_use: Use when you need a quick, read-only snapshot from a router that already has router-diag available, especially for interfaces, firewall, VPN, or health visibility.
---

# Router diag operator (read-only)

Use this skill when you need a narrow operational snapshot from `router-diag`
without changing router state.

This skill is observational only.

## Hard boundaries

Allowed:
- run `router-diag show interfaces`
- run `router-diag show firewall`
- run `router-diag show vpn`
- run `router-diag show health`
- if `router-diag` is not installed in PATH, run the packaged command from this repo with `nix run .#router-diag -- show <topic>`
- summarize what the command reported, including obvious missing dependencies or unavailable services

Do not:
- run any mutating network or service command such as `ip link set`, `ip route add`, `nft add/delete`, `wg set`, `tailscale up/down`, `systemctl restart`, or `nixos-rebuild`
- turn this into generic "fix networking" behavior
- edit configuration, apply remediation, or suggest live recovery steps as if they were already authorized
- infer canonical site topology or source-of-truth ownership from command output alone

## Approved command set

Prefer only these command forms:

```bash
router-diag show interfaces
router-diag show firewall
router-diag show vpn
router-diag show health
```

If the package is not installed on the target but you are operating from this repo,
use:

```bash
nix run .#router-diag -- show interfaces
nix run .#router-diag -- show firewall
nix run .#router-diag -- show vpn
nix run .#router-diag -- show health
```

Do not widen beyond these four `show` topics in this skill.

## Execution loop

1. Pick the smallest single `show` command that matches the question.
2. Run only the requested or clearly relevant `show` command(s).
3. Report the raw observation and any command-level limitation such as missing `nft`, `wg`, `tailscale`, or inactive health units.
4. If the output suggests a deeper topology or policy question, hand off interpretation to the consuming environment repo rather than guessing here.

## Boundary reminder

`router-diag` exposes runtime observations from the system it runs on. It does not
by itself tell you which interface should be WAN, which node should be active, or
which topology is intended. That source-of-truth may still live in the consuming
environment repo such as `unified-nix-configuration`.

## Stop conditions

Stop when all of the following are true:
- the requested read-only `show` command or commands have run, or you have reported why they could not run
- the output has been summarized without proposing mutation
- any ambiguity about intended topology, interface ownership, promotion policy, or site-specific meaning has been explicitly handed off to the consuming environment repo

If the next step would require changing live state, stop and hand off instead of
continuing.
