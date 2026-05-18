# Router Zones

`router-zones` is a forward-only policy layer for `router-firewall`.

It is intentionally narrow:

- it only governs forwarded traffic
- it does not manage router-local input
- it does not accept raw nftables fragments
- unmatched traffic falls back to the base `router-firewall` policy by default

That support boundary is deliberate. The goal of the first release is safe
composition, not a broad zone language.

## Composition Contract

- `services.router-firewall.enable = true` is required.
- `router-zones` dispatches in the `forward` chain based on ingress interface,
  after the base conntrack safety rules and before role-specific forwarding
  chains.
- A zone can take one of four default actions for unmatched forwarded traffic:
  `accept`, `drop`, `reject`, or `return`.
- The default is `return`, which hands control back to the base
  `router-firewall` policy.
- Router-local input is still owned by `router-firewall` and its role-specific
  chains (`WAN_LOCAL`, `LAN_LOCAL`, `MGMT_LOCAL`).

## Supported Surface

```nix
services.router-zones = {
  enable = true;

  zones = {
    wan.interfaces = [ "eth0" ];
    lan = {
      interfaces = [ "eth1" ];
      defaultForwardAction = "return";
    };
    iot = {
      interfaces = [ "eth2" ];
      defaultForwardAction = "drop";
    };
  };

  policies = [
    {
      fromZone = "lan";
      toZone = "wan";
      action = "accept";
    }
    {
      fromZone = "iot";
      toZone = "wan";
      action = "accept";
    }
    {
      fromZone = "iot";
      toZone = "lan";
      action = "drop";
    }
  ];
};
```

## What It Does Not Do Yet

- no router-local per-zone input policy
- no per-policy port matching
- no raw `extraRules` passthrough
- no HA-aware ownership model

Those are follow-on design questions. This module is meant to be correct and
explicit before it grows.
