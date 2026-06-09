# 87 - Router Apply-Safety and Rollback Runbook

## Status: `done`

## Objective

Document a bounded operational procedure for risky router updates so operators
and agents do not treat `nixos-rebuild switch` as self-validating when firewall,
DHCP, DNS, or routing changes could break live connectivity.

Suggested branch: `docs/router-apply-safety-runbook`

## Rationale

Recent live experience shows that some router updates can leave the network in a
bad state until the router is rebooted into an earlier generation.

Discussion 16 sharpened the real lesson from the OpenBSD comparison:

- the repo has generation rollback
- but it does not yet present a clear **acceptance procedure** for risky live
  changes

That gap matters most for updates that can break:

- SSH reachability
- LAN DNS
- DHCP lease behavior
- or upstream routing/WAN access

The immediate goal is not to automate rollback yet.
It is to make the manual safety procedure explicit and repeatable.

## Requirements

- [x] Add a repo-local doc for risky update procedure, likely
      `docs/router-apply-safety.md`
- [x] Define what counts as a risky change, including at least:
      - firewall changes
      - DNS service changes
      - DHCP service changes
      - WAN / HA / routing changes
- [x] Document the minimum pre-change preparation, including:
      - identify the previous generation
      - ensure console / Proxmox / out-of-band recovery path is known
      - identify another LAN vantage point when available
- [x] Document post-switch checks from another host where possible, including:
      - SSH reachability
      - DNS resolution through the router
      - WAN connectivity
      - and a way to tell whether DHCP or DNS is the likely failed layer
- [x] Document the rollback path explicitly:
      - `nixos-rebuild switch --rollback` when still reachable
      - reboot into previous generation when not reachable but console exists
- [x] Make it clear that an agent behind the broken router cannot recover
      reliably unless rollback or out-of-band access was prepared beforehand
- [x] Cross-link the new procedure from the HA / DHCP / hardening docs where
      operators are most likely to need it

## Verification

- [x] An operator can answer:
      - what to do before a risky router update
      - what to check immediately after it
      - and how to roll back if DNS or DHCP appears broken
- [x] The repo no longer leaves rollback procedure as oral tradition or incident
      memory
- [x] The doc is explicit about the difference between:
      - generation rollback
      - post-change health verification
      - and fully automated rollback

## Notes

This item is about **manual operational safety**.

It should not silently grow into a first implementation of auto-rollback logic.
