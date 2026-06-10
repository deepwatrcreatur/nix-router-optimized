# router-openvpn

`router-openvpn` is a router-shaped wrapper around `services.openvpn.servers`.

It does not try to hide OpenVPN itself. Instead, it keeps the native OpenVPN
configuration model and adds the router-specific pieces that are usually missing:

- trusted-interface integration with `router-firewall`
- WAN TCP/UDP port exposure per instance
- optional forwarding from the VPN tunnel to WAN

Example:

```nix
{
  imports = [ router-optimized.nixosModules.router-openvpn ];

  services.router-openvpn.instances.roadwarrior = {
    interfaceName = "tun0";
    wanUdpPorts = [ 1194 ];
    config = ''
      dev tun0
      proto udp
      port 1194
      server 10.30.0.0 255.255.255.0
      keepalive 10 60
      persist-key
      persist-tun
      ca /run/agenix/openvpn-ca.crt
      cert /run/agenix/openvpn-server.crt
      key /run/agenix/openvpn-server.key
      dh none
      topology subnet
    '';
  };
}
```

The router-firewall integration is optional. If `router-firewall` is imported,
the module can expose WAN ports and add trusted/forwarding rules; otherwise it
only manages the OpenVPN instances themselves.

## Credential Boundary

Keep OpenVPN secrets in runtime-readable files referenced from the raw OpenVPN
configuration, for example:

- `auth-user-pass /run/agenix/openvpn-auth-user-pass`
- `ca /run/agenix/openvpn-ca.crt`
- `cert /run/agenix/openvpn-client.crt`
- `key /run/agenix/openvpn-client.key`

Avoid embedding usernames or passwords directly in Nix values. In particular,
the passthrough `authUserPass` surface comes from upstream `services.openvpn`
and is not the preferred router-facing path for secret material because it can
encourage store-visible credentials instead of runtime files.
