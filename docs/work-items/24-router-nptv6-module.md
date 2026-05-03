# 24 — NPTv6 Module (Network Prefix Translation)

## Status: `todo`

## Objective
Implement a high-level `services.router-nptv6` module that provides a NixOS abstraction for 1:1 IPv6 prefix translation using `nftables`.

## Rationale
Standard IPv6 VPN redirection fails when the local LAN prefix differs from the remote VPN prefix (BCP38 ingress filtering). NPTv6 (RFC 6296) allows translating a stable internal prefix (like a ULA or local GUA) to a dynamic external prefix (like a VPN GUA) without the stateful overhead and "ewww" factor of NAT66.

## Requirements
- [ ] Define `services.router-nptv6.enable` option.
- [ ] Define `services.router-nptv6.rules` as a list of mapping objects:
  ```nix
  {
    internalPrefix = "fd00:1::/64";
    externalInterface = "tailscale0";
    externalPrefix = "2001:db8:1::/64"; # Optional, can be auto-detected
  }
  ```
- [ ] Implement `nftables` rule generation using `snat` and `dnat` in the `nat` table (or `netdev` family if more efficient).
- [ ] Ensure integration with `services.router-firewall` to allow translated traffic.

## Verification
- [ ] NixOS VM test: Assert that packets from `internalPrefix` have their source address translated to the corresponding address in `externalPrefix` when exiting `externalInterface`.
