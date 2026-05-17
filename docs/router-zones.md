# Router Zones

The `router-zones` module provides a zone-based firewall policy management layer on top of `router-firewall`. It allows grouping interfaces into security zones and defining high-level policies for traffic between them.

## Features

- **Zone Definition**: Group multiple interfaces (physical, VLANs, overlays) into a single security zone.
- **Inter-Zone Policies**: Define explicit actions (accept, drop, reject) for traffic flowing from one zone to another.
- **Intra-Zone Policy**: Traffic within the same zone is subject to the zone's default forward policy unless explicit rules are added.
- **Input Policy**: Define default behavior for traffic destined for the router itself on a per-zone basis.
- **Extra Rules**: Attach specific nftables rule fragments to inter-zone policies for granular control (e.g., restricted port access).

## Configuration

```nix
services.router-zones = {
  enable = true;

  zones = {
    wan.interfaces = [ "eth0" ];
    lan = {
      interfaces = [ "eth1" "eth2" ];
      defaultForwardPolicy = "accept";
      defaultInputPolicy = "accept";
    };
    iot = {
      interfaces = [ "eth3" ];
      defaultForwardPolicy = "drop";
      defaultInputPolicy = "drop";
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
      extraRules = "ip daddr 10.10.10.50 tcp dport 8123 accept comment \"Allow IoT to Home Assistant\"";
    }
  ];
};
```

## Options

### `services.router-zones.zones`
An attribute set of zone definitions.

- `interfaces`: List of interface names. Each interface can belong to at most one zone.
- `defaultInputPolicy`: Action for traffic to the router (`accept`, `drop`, `reject`). Default: `drop`.
- `defaultForwardPolicy`: Action for traffic passing through the router (`accept`, `drop`, `reject`). Default: `drop`.

### `services.router-zones.policies`
A list of policy objects.

- `fromZone`: Source zone name.
- `toZone`: Destination zone name.
- `action`: Action for matching traffic (`accept`, `drop`, `reject`). Default: `accept`.
- `extraRules`: Raw nftables rules to insert before the action.

## Integration Notes

- Requires `services.router-firewall.enable = true`.
- Zone policies are enforced early in the `input` and `forward` chains using `extraInputEarlyRules` and `extraForwardEarlyRules`.
- Established and related traffic is still handled by the main firewall's stateful tracking before zone policies are evaluated.
