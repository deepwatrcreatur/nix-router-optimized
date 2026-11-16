# Module Authoring Guide

This guide documents the conventions used by router-oriented NixOS modules in
this flake. Use it when adding a new `router-<name>` wrapper around an upstream
NixOS service.

## Module Shape

Place new modules at `modules/router-<name>.nix` and use the standard NixOS
module function header:

```nix
{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-<name>;
  hasRouterOption = path: hasAttrByPath path options;
in
{
  options.services.router-<name> = {
    enable = mkEnableOption "router-aware <name> defaults";
  };

  config = mkIf cfg.enable {
    # ...
  };
}
```

Keep router wrapper options under `services.router-<name>`. Forward to the
upstream service under `services.<upstream>` inside `config`.

Use `mkDefault` when setting upstream service options so downstream users can
override the wrapper defaults:

```nix
services.tailscale = {
  enable = mkDefault true;
  port = mkDefault cfg.port;
};
```

Use plain assignments only when the wrapper is intentionally the source of
truth, such as generated firewall rules or appended `extraUpFlags`.

## Optional Integrations

Router modules should evaluate cleanly when optional peer modules are not
imported. Always check option existence before reading another module's config:

```nix
firewallEnabled =
  if hasRouterOption [ "services" "router-firewall" "enable" ] then
    (config.services.router-firewall.enable or false)
  else
    false;
```

Add optional config with `optionalAttrs`:

```nix
services = {
  headscale.enable = mkDefault true;
} // optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
  router-firewall = mkIf firewallEnabled {
    wanTcpPorts = [ cfg.port ];
  };
};
```

Avoid reading values that your module also writes in a way that creates
recursion. If a module only integrates when a peer module is explicitly enabled,
do not set that peer module's `enable` option from the integration block.

## Firewall Contract

Use `router-firewall` only when it is imported. A module must still work with
the native NixOS firewall or no firewall wrapper at all.

Use these router-firewall options consistently:

- `overlayInterfaces`: mesh VPN interfaces such as `tailscale0`, `nb-router`,
  or an explicit ZeroTier `ztXXXXXXXX` interface. Overlay interfaces get trusted
  input plus bidirectional forwarding with router LAN/management interfaces.
- `extraTrustedInterfaces`: trusted router-facing interfaces that are not mesh
  overlays, such as OpenVPN `tun` interfaces used for administration.
- `extraForwardRules`: custom nftables forwarding rules for cases like
  `routeToWan`, where a tunnel should forward to WAN interfaces.
- `wanUdpPorts` and `wanTcpPorts`: public listener ports exposed on WAN.

For native firewall fallback, set the upstream module's `openFirewall` when it
has one, or add `networking.firewall.allowedTCPPorts` /
`allowedUDPPorts` only when `router-firewall` is absent.

## Overlay VPN Modules

Overlay wrappers should follow the pattern in `router-tailscale.nix`,
`router-netbird.nix`, and `router-zerotier.nix`.

Minimum options usually include:

- `enable`
- `interfaceName`
- `port`
- `trustedInterface`
- `openFirewall`
- service-specific join/auth settings

Use `overlayInterfaces` when `trustedInterface = true`, and expose the UDP port
through `wanUdpPorts` when `openFirewall = true`.

Add assertions for collisions with other enabled overlay modules when the
wrappers bind UDP ports:

```nix
{
  assertion = !(otherEnabled && otherPort != null && cfg.port == otherPort);
  message = "services.router-<name> and services.router-<other> share UDP port ${toString cfg.port}.";
}
```

If an overlay has dynamic DNS resolver addresses, prefer an explicit stable
option like `dnsResolverAddress` so LAN DNS services can forward to a predictable
loopback address.

See `docs/overlay-vpn.md` for the user-facing overlay model.

## Routing And Sysctls

Prefer upstream routing options when they exist. For example,
`router-tailscale` and `router-netbird` forward `useRoutingFeatures` to their
upstream modules.

If the upstream module has no routing abstraction, set kernel forwarding
explicitly only when the wrapper option requires it:

```nix
boot.kernel.sysctl = mkIf needsForwarding {
  "net.ipv4.ip_forward" = mkDefault 1;
  "net.ipv6.conf.all.forwarding" = mkDefault 1;
};
```

## Flake Registration

Register every new module in `flake.nix`:

```nix
nixosModules = {
  default = {
    imports = [
      self.nixosModules.router-<name>
    ];
  };

  router-<name> = import ./modules/router-<name>.nix;
};
```

Add the module to `nixosModules.default` only if it is safe to import when
disabled. Modules using `mkEnableOption` or empty attrset defaults should be
safe. If a module requires heavy mandatory configuration at import time, fix the
module shape instead of leaving it out of the default bundle.

Do not add module-specific settings to `nixosConfigurations.router-example`
unless the example needs a realistic integration scenario. Prefer eval checks in
`tests/` for module coverage.

## Documentation

Add `docs/router-<name>.md` with:

- a short summary of the upstream service and wrapper behavior
- a minimal Nix example
- an options table
- integration notes for firewall, DNS, Caddy, or other router modules
- operational steps that should not be hidden in declarative config, such as
  creating a Headscale pre-auth key in the controller

If the module participates in the overlay model, update `docs/overlay-vpn.md`.

Add or update the relevant work item in `docs/work-items/` and remove completed
items from the active queue in `docs/work-items/README.md`.

## Code Comment Tags

Most comments in this repo explain *what* code does, which the code already
shows. The comments that save the next contributor (human or coding agent)
time explain what the code cannot show: why a choice was made, and which
external behaviour or invariant breaks if it is "simplified". Mark those with
one of these tags so they can be found with a single grep:

| Tag | Use it for | Example |
| --- | --- | --- |
| `# WHY:` | a non-obvious decision and the alternative that was rejected | `# WHY: copytruncate, because Suricata keeps eve.json open` |
| `# GOTCHA:` | surprising behaviour of an external system the code depends on | `# GOTCHA: Technitium returns HTTP 200 for invalid-token` |
| `# INVARIANT:` | a property that must keep holding; name the check that enforces it | `# INVARIANT: only records listed in the state file are pruned (tests/...)` |
| `# SECURITY:` | a permission, trust or secret-handling boundary | `# SECURITY: token copy is 0640 root:router-dashboard` |
| `# UPSTREAM:` | a workaround tied to nixpkgs/upstream behaviour, with when it can go | `# UPSTREAM: nixpkgs suricata defaults outputs to null` |
| `# TODO(#123):` | deferred work, always with an issue number | |

Guidelines:

- One to three lines. When the full story is longer, put it in `docs/` and
  point to the heading, so readers can find it without scrolling past it:
  `# WHY: docs/router-technitium-automation.md#static-host-records-and-pruning`
- Do not narrate what the next line does.
- Put the tag on the line above the code it protects, not at the top of the file.
- When a tagged comment stops being true, fix or delete it in the same change.
- Before changing a module, read its tagged comments:

  ```sh
  rg -n '# (WHY|GOTCHA|INVARIANT|SECURITY|UPSTREAM|TODO)' modules/<file>.nix
  ```

### Doc comments for library functions

Functions other files call (for example `modules/lib/ip.nix`) get
[RFC 145](https://github.com/NixOS/rfcs/pull/145) doc comments: `/** ... */`
directly above the binding, written in Markdown. They describe what the
function takes and returns, with an `# Example` section when it helps, and
known limits under a heading. nixfmt keeps them attached to their binding,
and nixdoc, Noogle and `nix repl`'s `:doc` can read them.

~~~nix
/**
  Whether `cidrParent` contains every address of `cidrChild`.

  # Example

  ```nix
  cidrContains "10.0.0.0/8" "10.1.0.0/16"
  => true
  ```
*/
cidrContains = cidrParent: cidrChild: ...
~~~

Use `#` comments, not doc comments, for private helpers and for the tags
above. Module options are documented by their `description`, not by
comments.

## Lessons From Production

Bugs that reached a live router, and the rule each one implies for new modules:

- **Check the API's own status, not just the HTTP code.** Technitium answers
  errors (including `invalid-token`) with HTTP 200. Scripts using only
  `curl -f` reported success for weeks while block lists were never applied.
  Parse the JSON status and fail when it is not `ok`.
- **"active (exited)" proves nothing.** A oneshot unit can exit 0 without
  applying anything. Document a command that checks the *result* in the
  managed service (see `docs/router-technitium-automation.md`).
- **Check the upstream module's defaults for anything you rely on.** The
  nixpkgs Suricata module defaults `settings.outputs` to `null`, so the
  wrapper ran a sensor that recorded nothing. When wrapping an upstream
  module, list which upstream defaults the wrapper depends on and set them
  explicitly.
- **Sync units must also delete.** An add-only sync leaves state behind
  forever (retired hosts kept resolving). If a module creates objects in an
  external system, track what it created and remove what is no longer
  declared, touching only objects it owns.
- **Mind the sandbox.** Upstream units often use `ProtectSystem=strict`,
  `DynamicUser`, or `/var/lib/private`. A new path needs `ReadWritePaths` or
  `ReadOnlyPaths`, and `DynamicUser` state is not readable by other services.
  Copy a narrowly permissioned snapshot instead.
- **Prefer one recovering credential path over several static ones.** A
  self-healing bootstrap token is better than an age secret that goes stale
  silently. If an option has a legacy default (like
  `apiKeySecretName = "technitium-api-key"`), say in its description and docs
  which path is recommended.
- **Expose it as an option so consumers do not hand-roll it.** A consumer
  re-implemented `router-technitium.rfc2136` in their own unit, and that copy
  was the one with the stale-token bug. Mention existing options in the README
  module list so they are discoverable.

## Evaluation Tests

Eval checks live under `tests/` and are exported by `tests/default.nix`.

Use `tests/vpn-smoke.nix` for router VPN and overlay behavior. Use
`tests/doc-examples.nix` for examples copied into docs. For a new topic, add a
focused test file and import it from `tests/default.nix`.

Basic smoke check pattern:

```nix
router-<name>-standalone-eval = eval.mkNixosEvalCheck "router-<name>-standalone" [
  self.nixosModules.router-<name>
  {
    services.router-<name>.enable = true;
  }
  ({ config, ... }: {
    assertions = [
      {
        assertion = config.services.<upstream>.enable;
        message = "router-<name> should enable the upstream service.";
      }
    ];
  })
];
```

Add at least these cases when relevant:

- standalone eval without optional peer modules
- eval with `router-firewall`
- eval with any optional peer module integration, such as Caddy or
  `router-tailscale`
- failure checks for required options or port collisions
- doc-example eval for examples shown in `docs/router-<name>.md`

Validate with targeted checks first, then run the full flake check before
opening a PR:

```bash
nix build .#checks.x86_64-linux.router-<name>-standalone-eval
nix flake check
```

On this repo, `nix flake check` may report that `aarch64-linux` checks are
omitted as incompatible when running on an x86_64 host. Record that in the PR
validation notes instead of treating it as a local failure.
