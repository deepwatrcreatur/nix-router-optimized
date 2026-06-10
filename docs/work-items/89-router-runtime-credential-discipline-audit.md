# 89 - Router Runtime Credential Discipline Audit

## Status: `in-progress`

## Objective

Audit router monitoring, tunnel, VPN, and adjacent modules for how runtime
credentials are passed to services, and tighten any remaining surfaces that
still expose secrets too loosely.

Suggested branch: `chore/router-runtime-credential-audit`

## Rationale

Discussion 16 concluded that one useful lesson from the OpenBSD router is not a
new feature but a discipline:

- prefer protected runtime files or equivalent credential-loading mechanisms
- avoid casual secret exposure in process arguments or broad environment leakage

This repo already does some of this well, but the surface has grown:

- tunnels
- VPN modules
- DDNS
- monitoring/agent-style services

and it is worth checking that the current implementation story remains coherent
across modules rather than relying on case-by-case memory.

## Requirements

- [x] Inventory credential-passing patterns across relevant modules, including at
      least:
      - tunnel modules
      - VPN modules
      - DDNS / DNS-adjacent modules
      - monitoring or agent-like services
- [x] Identify any cases where credentials are exposed through:
      - process arguments
      - plain environment variables
      - or store-embedded config that should instead use runtime files or
        equivalent safer loading paths
- [x] Keep the audit grounded in existing repo patterns rather than inventing a
      brand-new secret system
- [x] If concrete fixes are small and local, land them; otherwise document the
      remaining cases clearly for follow-on work
- [x] Update docs where the intended runtime-file boundary is under-specified

## Verification

- [x] A reviewer can read one outcome artifact and understand which modules are:
      - already aligned
      - need tightening
      - or intentionally use a different safe pattern
- [x] The repo's credential-handling story is more consistent after the audit
- [x] No fix silently embeds secrets in the Nix store

## Notes

This item is about **discipline and consistency**, not about replacing agenix,
creating a broker, or redesigning secret authority.
