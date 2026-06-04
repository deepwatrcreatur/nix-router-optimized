# 81 - Router NDPPD Module and HA Ownership Assertions

## Status: `ready`

## Objective

Implement the minimum honest first slice for NDP proxying in
`nix-router-optimized` by adding a bounded `ndppd`-backed module with explicit
HA ownership assertions.

Suggested branch: `feat/router-ndppd-module`

## Rationale

Discussion 15 left a deliberately narrow implementation opening:

- do not expose four peer backends
- if anything ships near-term, make it a single advanced opt-in surface
- center it on `ndppd`
- and refuse ambiguous HA combinations rather than pretending VRRP failover
  automatically makes NDP proxying safe

That means the implementation question is not “how do we support every NDP
topology?”
It is:

- can the repo add one honest Linux/NixOS `ndppd` path
- with a normalized option surface
- and with the same kind of single-active-owner guardrail already required in
  adjacent HA-sensitive areas

## Requirements

- [ ] Add a bounded module, preferably `modules/router-ndp-proxy.nix`
- [ ] Export it from `flake.nix` as an explicit named module without silently
      widening `nixosModules.default`
- [ ] Use a normalized consumer-facing option surface rather than raw
      `ndppd.conf` passthrough, covering at minimum:
      - enable flag
      - upstream interface
      - downstream interface or interfaces
      - any small set of first-slice prefix/behavior options justified by the
        contract item
- [ ] Generate deterministic `ndppd` configuration and a managed systemd service
      from that option surface
- [ ] Add an HA ownership assertion comparable in spirit to the existing
      `router-bgp` rule so the module does **not** silently support ambiguous
      `router-ha` combinations
- [ ] Ensure the service behavior and module messaging make the intended support
      stance visible:
      - advanced/opt-in
      - single-active-owner only when HA is present
      - no implication of multi-active support
- [ ] Keep the implementation intentionally narrow rather than turning the first
      PR into a generic backend abstraction layer

## Verification

- [ ] A consumer can enable one declarative `ndppd`-based module without writing
      raw service glue by hand
- [ ] Ambiguous `router-ha` combinations fail clearly at eval time instead of
      appearing supported
- [ ] The generated config/service surface is deterministic and inspectable
- [ ] The implementation does not claim support for deferred/out-of-scope tools

## Notes

This item is about the **module and its ownership guardrails**.

It should not sprawl into:

- `ndpresponder` packaging
- generic multi-backend abstraction
- or broad NDP/dashboard observability work beyond what the first slice needs
