# router-zerotier

`router-zerotier` is a thin router-oriented wrapper around the NixOS
`services.zerotierone` module.

It adds three router-specific behaviors:

- enables kernel IP forwarding by default so ZeroTier can carry routed subnets
- plugs the ZeroTier interface into `router-firewall` via the
  `overlayInterfaces` list when enabled
- opens the WAN UDP port through `router-firewall` instead of requiring a
  separate firewall stanza

The default UDP port is **9993**, matching ZeroTier's upstream default.

## Example

```nix
{
  imports = [ router-optimized.nixosModules.router-zerotier ];

  services.router-zerotier = {
    enable = true;
    interfaceName = "zt3jnkd4l9";
    joinNetworks = [ "a8a2c3c10c1a68de" ];
    secretFile = "/run/agenix/zerotier-identity-secret";
  };
}
```

ZeroTier interface names are derived from the joined network and look like
`ztXXXXXXXX`. Set `interfaceName` to the actual runtime interface name when
`trustedInterface = true`, which is the default. Without the exact name,
`router-firewall` cannot safely generate overlay interface rules.

After the daemon starts, authorize the router member and configure managed
routes in ZeroTier Central or your self-hosted controller. The module joins the
networks locally, but route approval and network membership remain controller
policy.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the module |
| `interfaceName` | `null` | Exact `ztXXXXXXXX` interface name for router-firewall |
| `joinNetworks` | `[]` | ZeroTier network IDs to join on startup |
| `port` | `9993` | ZeroTier UDP port |
| `useRoutingFeatures` | `"server"` | IP forwarding level (`none`/`client`/`server`/`both`) |
| `trustedInterface` | `true` | Add to `router-firewall` overlay interfaces |
| `openFirewall` | `true` | Open UDP port on WAN |
| `secretFile` | `null` | Path to an `identity.secret` file for a persistent node ID |

## Persistent identity

ZeroTier stores the node identity in
`/var/lib/zerotier-one/identity.secret`. To keep a stable node ID across
reinstalls or ephemeral roots, provide that file through your secret manager:

```nix
services.router-zerotier.secretFile = "/run/agenix/zerotier-identity-secret";
```

The module copies it into place before `zerotierone.service` starts.

## Self-hosted controllers

ZeroTier networks can be controlled by the hosted ZeroTier Central service or
by a self-hosted controller such as `ztncui` or ZeroTierOne's built-in
controller mode. This module only configures the router client; controller
setup and route authorization are managed outside the wrapper.

## Interaction with other overlays

Tailscale, Netbird, and ZeroTier can run on the same router as long as their UDP
ports are distinct. With defaults there is no conflict:

- Tailscale: UDP 41641
- Netbird: UDP 51821
- ZeroTier: UDP 9993

If you override ports and collide with another enabled router overlay module,
evaluation fails with an assertion.

See `overlay-vpn.md` for the shared firewall model.
