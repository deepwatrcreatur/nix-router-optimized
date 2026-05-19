# Router Security Hardening

`router-security-hardened` is a narrow hardening companion for
`router-firewall`.

It currently provides three independent capabilities:

- kernel and network sysctl hardening
- WAN-scoped Geo-IP input blocking
- forward-path MAC whitelist enforcement

The scope is intentionally explicit:

- Geo-IP blocking applies only to traffic entering configured WAN interfaces.
- MAC security applies only to forwarded traffic, not router-local input.
- Geo-IP refresh tolerates download failure and preserves the currently loaded
  nftables set rather than flushing it empty.

## Example

```nix
services.router-firewall = {
  enable = true;
  wanInterfaces = [ "eth0" ];
};

services.router-security-hardened = {
  enable = true;

  kernelHardening.enable = true;

  geoIpBlocking = {
    enable = true;
    blockedCountries = [ "ru" "cn" "ir" ];
  };

  macSecurity = {
    enable = true;
    policy = "enforce";
    whitelists."br-lan" = [
      "00:11:22:33:44:55"
      "AA:BB:CC:DD:EE:FF"
    ];
  };
};
```

## Notes

- `services.router-firewall.enable = true` is required for Geo-IP and MAC
  policy features.
- Geo-IP data is fetched from IPDeny over HTTPS.
- MAC allowlists are enforced in the `forward` chain via a dedicated helper
  chain inserted before the base router-forwarding policy.
