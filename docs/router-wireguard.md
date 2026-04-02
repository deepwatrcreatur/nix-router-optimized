# router-wireguard

`router-wireguard` wraps `networking.wireguard.interfaces` with router-shaped
defaults:

- optional WAN UDP port exposure through `router-firewall`
- optional trusted-interface integration for LAN reachability
- optional WireGuard-client forwarding to WAN

Example:

```nix
{
  imports = [ router-optimized.nixosModules.router-wireguard ];

  services.router-wireguard = {
    enable = true;
    interfaceName = "wg0";
    ips = [ "10.20.0.1/24" ];
    privateKeyFile = "/run/agenix/wg-router-key";
    peers = [
      {
        publicKey = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
        allowedIPs = [ "10.20.0.2/32" ];
        persistentKeepalive = 25;
      }
    ];
  };
}
```

The router-firewall integration is optional. If `router-firewall` is imported,
the module can open the WAN UDP port and treat the tunnel as trusted; otherwise
it only configures native WireGuard.
