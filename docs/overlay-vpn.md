# Overlay VPN Integration

This flake ships router-aware wrapper modules for mesh VPN overlays — networks
that create a virtual interface over the public internet and let you reach
devices by stable private addresses regardless of where they physically are.

The currently supported overlays are:

| Module | Upstream service | Interface | Default port |
|--------|-----------------|-----------|--------------|
| `router-tailscale` | Tailscale | `tailscale0` | UDP 41641 |
| `router-netbird` | Netbird | `nb-router` | UDP 51821 |
| `router-zerotier` | ZeroTier | user-provided `ztXXXXXXXX` | UDP 9993 |

---

## The overlayInterfaces abstraction

`router-firewall` maintains a list called `overlayInterfaces`. Any interface
listed there receives:

- **unrestricted input** — overlay peers can reach the router itself
- **overlay-originated forwarding** — overlay peers can reach all router
  interfaces (WAN, LAN, management)
- **trusted return forwarding** — LAN/management/trusted interfaces can reach
  overlay peers

Each per-overlay module (`router-tailscale`, `router-netbird`,
`router-zerotier`, …) appends its interface name to this list automatically
when `trustedInterface = true` (the default). You do not need to set
`overlayInterfaces` manually for normal use.

```nix
# What happens automatically when you enable both modules:
services.router-firewall.overlayInterfaces = [ "tailscale0" "nb-router" ];
```

This generates the following nftables rules for each overlay interface:

```text
# input chain
iifname "tailscale0" accept
iifname "nb-router"  accept

# forward chain
iifname "tailscale0" oifname {wan, lan, mgmt, …} accept
iifname {lan, mgmt, …} oifname "tailscale0" accept
iifname "nb-router"  oifname {wan, lan, mgmt, …} accept
iifname {lan, mgmt, …} oifname "nb-router"  accept
```

---

## Tailscale

```nix
services.router-tailscale = {
  enable = true;
  authKeyFile = "/run/agenix/tailscale-auth-key";
  advertiseRoutes = [ "10.10.0.0/16" ];
  advertiseExitNode = false;
};
```

Tailscale runs a coordination server at `login.tailscale.com`. Routes and ACLs
are configured in the Tailscale admin console. Subnet advertisement is
controlled with `tailscale up --advertise-routes`, which this module drives from
the `advertiseRoutes` option.

DNS: Tailscale's MagicDNS resolves `*.ts.net` via `100.100.100.100`. If you
run Technitium or Unbound as your LAN resolver, add a conditional forwarder:
`ts.net → 100.100.100.100`.

---

## Netbird

```nix
services.router-netbird = {
  enable = true;
  setupKeyFile = "/run/agenix/netbird-setup-key";
};
```

Netbird can use the hosted coordination server (`app.netbird.io`) or a
self-hosted management stack. Subnet routes are configured in the management
console after the peer registers — the client only needs
`useRoutingFeatures = "server"` to enable kernel IP forwarding, which is the
default in this module.

DNS: Netbird resolves its mesh domain via its own DNS resolver. Pin it to a
stable loopback address for Technitium/Unbound forwarding:

```nix
services.router-netbird = {
  enable = true;
  setupKeyFile = "/run/agenix/netbird-setup-key";
  dnsResolverAddress = "127.0.0.2";
};
```

Then add a conditional forwarder in Technitium/Unbound pointing your Netbird
domain (e.g. `netbird.cloud` or your self-hosted domain) at `127.0.0.2:53`.

---

## ZeroTier

```nix
services.router-zerotier = {
  enable = true;
  interfaceName = "zt3jnkd4l9";
  joinNetworks = [ "a8a2c3c10c1a68de" ];
  secretFile = "/run/agenix/zerotier-identity-secret";
};
```

ZeroTier can use the hosted ZeroTier Central controller or a self-hosted
controller. Network membership and managed routes are authorized in that
controller; the router module joins the network locally and enables IP
forwarding by default.

ZeroTier names interfaces dynamically (`ztXXXXXXXX`), so `interfaceName` has no
safe default. Set it to the actual interface name before using the default
`trustedInterface = true` firewall integration.

---

## Running both at the same time

Running multiple overlays simultaneously on the same router is a legitimate but
intentional configuration. Common reasons:

- **Migration**: zero-downtime transition between the two
- **Multi-org**: corporate Tailscale tailnet + self-hosted homelab Netbird mesh
- **Redundancy**: fallback connectivity if one coordination server is unreachable

### Port conflicts

The wrappers default to distinct ports: `router-tailscale` uses UDP 41641,
`router-netbird` uses UDP 51821, and `router-zerotier` uses UDP 9993. If you
override ports, an assertion will fire if enabled router overlay modules
collide.

### DNS coexistence

Each overlay manages a different DNS domain. Configure your LAN resolver to
forward each domain to its respective resolver:

```text
# Technitium example (conditional forwarders)
ts.net           → 100.100.100.100   (Tailscale MagicDNS)
netbird.cloud    → 127.0.0.2:53      (Netbird, with dnsResolverAddress set)
```

Unbound equivalent:

```yaml
forward-zone:
  name: "ts.net."
  forward-addr: 100.100.100.100

forward-zone:
  name: "netbird.cloud."
  forward-addr: 127.0.0.2@53
```

### Example: both enabled

```nix
services.router-tailscale = {
  enable = true;
  authKeyFile = "/run/agenix/tailscale-auth-key";
  advertiseRoutes = [ "10.10.0.0/16" ];
};

services.router-netbird = {
  enable = true;
  setupKeyFile = "/run/agenix/netbird-setup-key";
  dnsResolverAddress = "127.0.0.2";
  # port defaults to 51821 — no collision with Tailscale's 41641
};
```

---

## Adding a new overlay VPN module

Follow this pattern when wrapping a new mesh VPN:

1. Create `modules/router-<name>.nix`
2. Expose at minimum: `enable`, `interfaceName`, `port`, `trustedInterface`,
   `openFirewall`
3. In `config`, set:
   ```nix
   services.router-firewall = mkIf (hasRouterOption [...] && firewallEnabled) {
     overlayInterfaces = mkIf cfg.trustedInterface [ cfg.interfaceName ];
     wanUdpPorts = mkIf cfg.openFirewall [ cfg.port ];
   };
   ```
4. Add an assertion if the port can conflict with another overlay module
5. Register in `flake.nix` under both `nixosModules.default` imports and the
   named `nixosModules.<name>` attribute
6. Add `docs/router-<name>.md` and a `docs/work-items/` entry for tests

See `router-tailscale.nix` and `router-netbird.nix` as reference implementations.
