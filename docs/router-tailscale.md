# router-tailscale

`router-tailscale` is a thin router-oriented wrapper around the native NixOS
`services.tailscale` module.

It adds three router-specific behaviors:

- configures `tailscale up` flags from declarative options like
  `advertiseRoutes`, `advertiseExitNode`, and `acceptRoutes`
- plugs the Tailscale interface into `router-firewall` when enabled
- opens the WAN UDP port through `router-firewall` instead of requiring a
  separate firewall stanza

Example:

```nix
{
  imports = [ router-optimized.nixosModules.router-tailscale ];

  services.router-tailscale = {
    enable = true;
    authKeyFile = "/run/agenix/tailscale-auth-key";
    advertiseRoutes = [ "10.10.0.0/16" "192.168.100.0/24" ];
    enableSsh = true;
  };
}
```

When used in a repo that already has host-level Tailscale wiring, prefer one
source of truth. If another layer already enables `services.tailscale` or runs
`tailscale up`, use either the upstream router module or the repo-local aspect,
not both.

With `authKeyFile` set, nixpkgs' `tailscaled-autoconnect` unit waits for
Tailscale to reach `Running`. A router can boot without Internet for longer
than that unit's 90 s start timeout: a cold start of the whole site, or an HA
member that stays BACKUP until VRRP promotes it. The module therefore restarts
the unit every 15 s until it succeeds, instead of leaving it failed.

The router-firewall integration is opportunistic: if `router-firewall` is also
imported, the module wires the Tailscale interface and WAN UDP port into that
policy. If not, it falls back to the native `services.tailscale` behavior.
