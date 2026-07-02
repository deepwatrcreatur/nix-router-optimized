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
- **Consumer-owned single-active units** through
  `services.router-ha.singleActiveUnits`

That does **not** mean every LAN-facing service is promotion-aware by default.

`singleActiveUnits` is intentionally generic:

- it starts listed units on master promotion
- it stops them on backup or fault transitions
- and it records the current runtime role in `/run/router-ha/role`

That runtime surface exists so consumer configs can express their own
ExecCondition or startup policy without upstream claiming typed ownership for
every service.

## Validated Consumer Pattern

The currently validated consumer pattern for a VRRP router pair is:

- let `router-ha` own **WAN/VIP role transition**
- let `router-ha.singleActiveUnits` own **specific single-owner runtime units**
- keep some services **shared on both nodes**
- keep some services **manual-promotion only**

In other words, do **not** collapse all router services behind one blanket
"backup becomes master, therefore everything should start" assumption.

### A practical split that is working

- **Promotion-aware / VRRP-owned**
  - WAN interface ownership via `services.router-ha.wan`
  - public DDNS update execution when the consumer makes both
    `inadyn.service` and `inadyn.timer` `singleActiveUnits`
  - any other service the consumer explicitly adds to
    `services.router-ha.singleActiveUnits`
- **Shared on both nodes**
  - `router-ntp` / Chrony, when the consumer wants standby time-sync
    continuity instead of single-owner NTP
  - passive/observability services such as Suricata when the deployment wants
    them running on both nodes
- **Still consumer-owned and often manual**
  - DHCP ownership for the current reference pair
  - any DNS, UPnP, or other LAN-facing service that the consumer has not wired
    explicitly behind a tested ownership boundary

### Minimal consumer sketch

```nix
{
  services.router-ha = {
    enable = true;
    role = "master"; # or "backup" per host
    virtualIp = "10.10.10.1/16";
    vrrpInterface = "br-lan";
    wan = {
      enable = true;
      interface = "wan0";
      clonedMac = "02:00:00:00:00:01";
    };
    singleActiveUnits = [
      "inadyn.service"
      "inadyn.timer"
    ];
  };

  services.router-ddns.enable = true;

  # Shared service example: keep Chrony on both nodes.
  services.router-ntp.enable = true;
}
```

That example is intentionally schematic. The important part is the **split of
ownership models**, not the literal placeholder values.

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

The current validated reference deployment uses the **first** of those choices:
Chrony available on both nodes.

What should not be assumed:

- that enabling `router-ha` implies Chrony ownership semantics
- that VRRP transitions automatically define the correct NTP behavior

## Support Boundary Summary

- **Supported upstream:** router NTP service itself
- **Not currently supported upstream:** a typed `router-ha` adapter for NTP
- **Expected policy owner:** consumer config

Likewise, `singleActiveUnits` support does **not** imply that upstream has
declared a first-class HA contract for whatever unit names a consumer lists.

For risky ownership, WAN, or failover changes, use
[`router-apply-safety.md`](./router-apply-safety.md) as the manual acceptance
and rollback procedure.
