# 76 - Consumer DNS Service Active-Owner Boundary and Technitium Clustering

## Status: `done`

## Objective

Decide whether the consumer-side LAN-facing DNS service should remain shared
across `router` and `router-backup` under Technitium clustering, or whether some
part of that surface should move behind `router.failover.activeOwner` without
pretending that DNS, DHCP, and failover ownership are the same problem.

## Rationale

The consumer-side `activeOwner` boundary now explicitly gates:

- public DDNS ownership
- `kea-dhcp4-server.service`
- `kea-dhcp-ddns-server.service`

That leaves one materially riskier next question:

- should `router-dns-service` / Technitium stay available on both routers as a
  clustered shared capability
- or is some LAN-facing DNS identity actually single-owner and therefore a
  better fit for `activeOwner`

This is riskier than DHCP because the current docs explicitly use Technitium
clustering to keep DNS/admin state aligned across both routers while also
warning that DHCP failover is still a different problem.

This item exists so another agent can answer that question deliberately instead
of collapsing DNS, DHCP, and failover into one unsafe change.

## Requirements

- [x] Read the current consumer-side DNS/Technitium boundary in:
      - `unified-nix-configuration/hosts/nixos/router/service-capability.nix`
      - `unified-nix-configuration/hosts/nixos/router/role.nix`
      - `unified-nix-configuration/hosts/nixos/router-backup/configuration.nix`
      - `unified-nix-configuration/docs/router-spare-cutover.md`
      - `unified-nix-configuration/docs/router-source-of-truth.md`
- [x] Decide whether LAN-facing DNS service is:
      - intentionally shared capability under clustering
      - partially single-owner
      - or a mixed boundary that needs a narrower split than a simple
        `enable = activeOwner`
- [x] If an `activeOwner` expansion is justified, keep it narrow and explain
      exactly which surface moves behind the gate
- [x] If shared DNS remains the right answer, document that explicitly so future
      agents do not keep trying to gate it casually
- [x] Keep DHCP failover, DNS clustering, and public DDNS ownership clearly
      separated in the resulting docs and outcome

## Verification

- [x] Operators can tell whether LAN DNS service is shared, single-owner, or
      split-boundary
- [x] The repo no longer leaves the DNS/Technitium ownership question as an
      implicit guess after the recent `activeOwner` expansions
- [x] Any chosen change remains compatible with the documented Technitium
      clustering stance

## Decision

LAN-facing DNS service remains an intentionally **shared capability** under
Technitium clustering.

The consumer tree should continue to separate:

- shared Technitium-backed LAN DNS/admin state on both routers
- single-owner public DDNS identity
- single-owner DHCP service ownership

So this item does **not** expand `router.failover.activeOwner` to
`services.router-dns-service.enable = activeOwner`.

## Outcome

The relevant consumer-side docs now say this explicitly:

- `router.failover.activeOwner` is a narrow single-owner boundary
- `services.router-dns-service` is intentionally not one of its consumers
- Technitium clustering is for shared LAN DNS/admin-state alignment, not a cue
  to collapse DNS, DHCP, and failover into one ownership switch

## Notes

This item is about **consumer-side DNS service ownership under HA**, not about
reintroducing two-node DHCP HA or changing the upstream `router-ha` adapter
boundary.
