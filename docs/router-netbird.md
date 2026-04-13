# router-netbird

`router-netbird` is a thin router-oriented wrapper around the NixOS
`services.netbird` module.

It adds three router-specific behaviors:

- sets `useRoutingFeatures = "server"` by default, enabling kernel IP forwarding
  so Netbird can advertise subnets configured in the management console
- plugs the Netbird interface into `router-firewall` via the `overlayInterfaces`
  list when enabled
- opens the WAN UDP port through `router-firewall` instead of requiring a
  separate firewall stanza

The default UDP port is **51821** (not the upstream default of 51820) so that
Tailscale and Netbird can be enabled simultaneously without binding the same
port.

## Example

```nix
{
  imports = [ router-optimized.nixosModules.router-netbird ];

  services.router-netbird = {
    enable = true;
    setupKeyFile = "/run/agenix/netbird-setup-key";
  };
}
```

After the daemon starts, register the router as a subnet router in the Netbird
management console (app.netbird.io or your self-hosted instance). The daemon
announces readiness but route approval happens server-side.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the module |
| `clientName` | `"router"` | `services.netbird.clients` entry name |
| `interfaceName` | `"nb-router"` | Netbird interface name |
| `port` | `51821` | WireGuard UDP port |
| `setupKeyFile` | `null` | Path to setup key file for automated join |
| `setupKeyDependencies` | `[]` | Systemd units to wait for before reading the key |
| `useRoutingFeatures` | `"server"` | IP forwarding level (`none`/`client`/`server`/`both`) |
| `trustedInterface` | `true` | Add to `router-firewall` overlay interfaces |
| `openFirewall` | `true` | Open UDP port on WAN |
| `logLevel` | `"info"` | Daemon log level |
| `hardened` | `true` | Run as dedicated user |
| `dnsResolverAddress` | `null` | Stable loopback address for the DNS resolver |
| `dnsResolverPort` | `53` | DNS resolver port when address is set |

## DNS configuration

Netbird's DNS resolver answers for the mesh domain (default `netbird.cloud` or
your self-hosted domain). When running alongside a LAN DNS server, pin the
resolver to a stable address so your DNS server can forward to it:

```nix
services.router-netbird.dnsResolverAddress = "127.0.0.2";
```

Then add a conditional forwarder in Technitium or Unbound pointing your Netbird
domain at `127.0.0.2`. See `overlay-vpn.md` for a complete dual-VPN example.

## Self-hosted management server

The module connects to whatever management server is baked into the setup key.
For self-hosting, generate the key in your own Netbird management console. The
NixOS `services.netbird.server` module (from nixpkgs) provides the server stack
if you want to run management, signal, dashboard, and relay on the same host or
a separate NixOS machine.

## Interaction with router-tailscale

Both modules can be enabled simultaneously. The only constraint is that they
must use different UDP ports — the assertion in `router-netbird` will fire if
they collide. With the defaults (Tailscale 41641, Netbird 51821) there is no
conflict.

See `overlay-vpn.md` for DNS coexistence configuration.
