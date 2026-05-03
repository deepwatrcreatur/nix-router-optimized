# 26 — Dynamic Prefix-Watch & Sync Hook

## Status: `todo`

## Objective
Implement a mechanism to automatically update NPTv6 rules and routing tables when dynamic IPv6 prefixes on VPN interfaces change.

## Rationale
Travel routers frequently encounter changing WAN and VPN prefixes. Static configuration of NPTv6 `externalPrefix` will break the connection when the remote site's prefix rotates. We need an automated "set-and-forget" mechanism for dynamic environments.

## Requirements
- [ ] Research and implement a `systemd-networkd` hook or a `udev` rule that triggers on IP address changes on specified interfaces (e.g., `tailscale*`, `nb-*`).
- [ ] Create a small script (or NixOS service) that:
    1.  Detects the current GUA prefix on the VPN interface.
    2.  Updates the active `nftables` NPT rules via `nft` command.
    3.  Updates the `ip -6 rule` if necessary.
- [ ] Ensure the script is robust against multiple interfaces and intermittent connectivity.
- [ ] Integrate this into the `services.router-nptv6` module as an `autoDetect` option.

## Verification
- [ ] Manual test: Manually change the IP on a dummy VPN interface and verify that the `nftables` NPT rule is updated within 5 seconds.
