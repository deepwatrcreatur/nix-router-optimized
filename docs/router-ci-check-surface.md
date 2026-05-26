# Router CI Check Surface

This note maps the current exported `checks` surface in
`nix-router-optimized`, identifies where the visible CI noise comes from, and
proposes the suite boundary that follow-up work should implement.

## Current Surface

Current exported count:

- `174` top-level `checks.x86_64-linux.*` leaves

Current large families:

| Family | Count | Why it exists today |
| --- | ---: | --- |
| `module-*` import smoke checks | `44` | one leaf per exported module to guarantee importability |
| docs / README example coverage | `26` | keeps examples and doc fragments CI-backed |
| dashboard and browser-contract checks | `18` | inventory, firewall, service-control, metadata, CSS, and runtime contract coverage |
| firewall / zones / security / HA boundary | `20` | policy guardrails and failure assertions |
| VPN / overlay / remote-access | `30` | WireGuard, OpenVPN, Tailscale, Headscale, Netbird, Zerotier, tunnels, remote admin |
| BGP / MWAN / IPv6 policy | `12` | BGP, IPv6 source-routing, PvD, and NPTv6 boundaries |
| Kea / DHCP / option 108 | `11` | DHCP, option 108, fallback, and unsupported-backend assertions |
| DNS / DDNS / HA DNS / Technitium | `7` | DNS64/NAT64, Technitium bootstrap, encrypted DNS, RFC2136 |
| CLAT runtime / observability | `4` | CLAT status and runtime-specific unit coverage |
| meta exports | `2` | default module bundle and exported module list |

These ten families already sum to the entire exported set. The problem is not
that the repo lacks categorization. The problem is that the categorization is
implicit in filenames and prefixes, while CI exports almost every leaf directly.

## Constructor Shape

The check constructors are also mixed:

- the surface is dominated by `mkNixosEvalCheck` / `mkNixosEvalFailureCheck`
  style leaves
- there are a smaller number of heavier `runCommand` style leaves for Python or
  Elixir unit suites and doc-example aggregation

Hotspots by file today include:

- `tests/vpn-smoke.nix`: `23` positive eval leaves and `4` failure leaves
- `tests/pro-features-smoke.nix`: `16` positive and `3` failure leaves
- `tests/router-zones.nix`: `3` positive and `6` failure leaves
- `tests/router-kea-eval.nix`: `5` positive and `3` failure leaves
- `tests/router-security-hardened.nix`: `4` positive and `2` failure leaves
- `tests/router-dashboard-inventory.nix`: `4` positive, `2` failure, and `1`
  runtime/unit leaf
- `tests/router-dashboard-service-control.nix`: `2` positive, `2` failure, and
  `1` runtime/unit leaf

That confirms the visible CI surface is not just “too many modules.” It is also
many small functional checks exported independently.

## What Should Stay Directly CI-Visible

The exported surface should stay small and legible. The top-level visible
boundary should answer:

- does the module graph still import
- do docs/examples still evaluate
- do the dashboard/browser contracts still hold
- do router service features still pass their major guardrails
- do routing/policy features still hold
- do overlay/remote-access features still hold
- do heavier runtime-style/unit suites still pass

That points to `6` or `7` top-level suites, not `174` top-level leaves.

## Proposed Target Exported Shape

Recommended default exported suites:

1. `ci-module-surface`
   - default bundle
   - exported module list
   - all `module-*` import smoke leaves
2. `ci-docs-and-examples`
   - README examples
   - docs examples
   - doc-boundary failure assertions
3. `ci-dashboard-contracts`
   - dashboard metadata leaves
   - browser-contract leaves
   - dashboard runtime/unit leaves
4. `ci-router-services`
   - DHCP / Kea
   - Technitium / DDNS / HA DNS
   - NAT64 / DNS64 / mDNS / UPnP
5. `ci-routing-and-policy`
   - firewall / zones / security
   - BGP
   - MWAN / PvD / NPTv6
   - HA boundary assertions
6. `ci-overlay-and-remote-access`
   - WireGuard / OpenVPN / Tailscale / Headscale
   - Netbird / Zerotier
   - Cloudflare tunnel / remote admin / tunnel metadata
7. `ci-runtime-heavy`
   - CLAT Python / Elixir unit leaves
   - other true runtime-style or multi-step unit suites

This stays within the intended `3`-to-`8` range while preserving a meaningful
human model of the repo.

## What Should Move Behind Coarser Suites

These leaves should generally stop being directly exported:

- all `module-*` import leaves individually
- most single-purpose docs example leaves
- most individual dashboard metadata/browser leaves
- most individual VPN / overlay leaves
- most single-feature policy leaves

They should still exist repo-locally for targeted developer use. The follow-up
implementation item should preserve narrow entry points rather than deleting the
underlying attrsets.

## Local-Only Boundary

The repo should keep a non-default local/debug surface for:

- one-off feature debugging
- failure-path reproduction
- targeted PR validation while iterating on a single module family

That means the follow-up should separate:

- **exported CI suites**
- **fine-grained local leaf checks**

instead of pretending both audiences need the same flake boundary.

## Obvious Duplicate or Shared Harness Opportunities

The current shape suggests repeated overhead in a few places:

- `44` independent module-import leaves all exercise the same basic importability
  contract
- many docs/example leaves likely share the same evaluation setup pattern
- many VPN / overlay leaves differ only in module stack and small option changes
- dashboard metadata and contract checks are numerous enough to justify explicit
  aggregation by family

This does **not** prove worker-second savings by itself. It does show where the
follow-up suite implementation should look first if the goal is fewer repeated
eval/setup costs instead of just fewer status lines.

## Follow-Up Boundary

This document is the decision input for:

- work item `78`: implement the suite boundary
- work item `79`: capture before/after `nix-ci.com` evidence

It is intentionally planning-only. It does not change the exported flake
surface in this PR.
