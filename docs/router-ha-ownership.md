# Router HA Ownership Boundary

`services.router-ha` in this repo is intentionally narrower than a general
"promote every service on the backup router" framework.

The current upstream stance is:

- some ownership patterns are supported explicitly
- some services remain consumer policy
- and some combinations are still intentionally blocked or deferred

This note exists so operators do not infer broader service orchestration than
the modules actually claim.

## Current Upstream Shape

Today the repo has bounded ownership behavior in these areas:

- **WAN role transitions** through `services.router-ha.wan`
- **Kea-related sync/control affordances** where explicitly configured
- **BGP single-active-owner behavior** where the `router-bgp` integration makes
  promotion semantics explicit

That does **not** mean every LAN-facing service is promotion-aware by default.

## NTP Boundary

`services.router-ntp` is **not** a typed `router-ha` ownership adapter today.

That means upstream does **not** claim that Keepalived transitions should
universally:

- start or stop `chronyd`
- change Chrony serving behavior automatically
- or define a one-size-fits-all ownership model for LAN-facing NTP service

Why this remains consumer-owned:

- Chrony often serves both upstream sync and downstream LAN clients at once
- the right ownership policy can depend on topology and operational intent
- some operators may want NTP serving on both nodes for management stability,
  while others may want strict single-owner service

So the current stance is explicit non-support for a typed upstream adapter, not
an accidental omission.

## What Upstream Does Guarantee

With `services.router-ntp.enable = true`:

- Chrony is configured as the NTP server
- LAN client access can be bounded by `lanSubnets`
- UDP 123 is opened on trusted interfaces when `router-firewall` is present

But `router-ha` does **not** add a Chrony-specific promotion/demotion hook.

## What Consumers Should Do

If a deployment needs LAN-facing NTP to follow an ownership model, the consumer
configuration should express that policy explicitly.

Examples of consumer-owned choices:

- keep Chrony available on both nodes
- gate Chrony behind a promoted-node profile
- couple NTP visibility to a broader active-service layer

What should not be assumed:

- that enabling `router-ha` implies Chrony ownership semantics
- that VRRP transitions automatically define the correct NTP behavior

## Support Boundary Summary

- **Supported upstream:** router NTP service itself
- **Not currently supported upstream:** a typed `router-ha` adapter for NTP
- **Expected policy owner:** consumer config
