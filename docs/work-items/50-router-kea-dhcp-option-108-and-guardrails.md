# 50 - Router Kea DHCP Option 108 and Guardrails

## Status: `done`

## Objective

Add an explicit RFC 8925 / DHCPv4 option `108` capability to `services.router-kea`
with the right declarative guardrails for IPv6-mostly deployments.

## Rationale

`router-kea` is the most natural first backend for this feature because the
module already renders structured `option-data` into the generated Kea config.

That makes Kea the best first place to implement option `108` cleanly, rather
than trying to force the feature into every backend at once.

But the repo should not expose it as a loose raw option blob. The useful value
here is in making the declarative intent explicit:

- this LAN is intentionally IPv6-mostly
- clients that ask for option `108` may forgo IPv4
- and the operator is expected to provide a working IPv6-only path

## Requirements

- [x] Add a declarative `router-kea` option surface for RFC 8925 / option `108`
      rather than requiring users to inject raw custom option data manually
- [x] Render the correct Kea `option-data` for subnet or scope configuration
- [x] Support configuration of the RFC `V6ONLY_WAIT` timer value
- [x] Add assertions or warnings that prevent obviously misleading use, such as:
      - enabling the option on a subnet that is not intended to be IPv6-mostly
      - enabling it without the repo's NAT64/DNS64 path or another explicit
        operator-acknowledged IPv6-only reachability story
- [x] Keep the feature opt-in and scoped; do not change existing Kea defaults for
      ordinary LANs

## Verification

- [x] Enabling the new `router-kea` option results in a concrete generated Kea
      config that advertises DHCP option `108`
- [x] The option can be disabled cleanly without changing normal DHCP behavior
- [x] New assertions/warnings surface the intended support boundary clearly
- [x] Focused eval coverage exists for both enabled and disabled cases

## Notes

This is the **first backend implementation** item.

It should stay narrow and not absorb:

- generic dashboard/UI work
- non-Kea backend support
- or deep client-interoperability test matrices

Those belong to follow-on items once the declarative Kea shape exists.
