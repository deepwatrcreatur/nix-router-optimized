# 25 — IPv6 VPN Policy Routing & Targeted NAT66

## Status: `todo`

## Objective
Enhance `router-networking` and `router-firewall` to support source-based routing decisions and targeted IPv6 masquerading (NAT66).

## Rationale
Users often want to redirect specific devices (e.g., a TV VLAN) through a VPN while keeping other traffic on the local WAN. This requires both a routing decision (Policy-Based Routing) and an address translation (NAT66) if NPTv6 is not feasible or the remote prefix is unknown.

## Requirements
- [ ] Add `vpnExit` option to `services.router-networking.routedInterfaces`.
- [ ] Implement `ip -6 rule` generation to route packets from the specified interface into a VPN-specific routing table.
- [ ] Add `services.router-firewall.ipv6Masquerade` option for specific output interfaces.
- [ ] Generate nftables `masquerade` rules in the `nat` table for the specified interfaces.
- [ ] Ensure that `router-firewall` automatically adds the necessary `fwmark` or `iifname` rules to trigger the policy routing.

## Verification
- [ ] NixOS VM test: Confirm that a packet from a "streaming" VLAN is correctly masqueraded and sent out the `tailscale0` interface, while a packet from the "mgmt" VLAN exits the standard WAN.
