# Discussion 15: Should `nix-router-optimized` Add NDP Proxy Daemons as Flake Options?

**Status:** open
**Opened:** 2026-05-28
**Seat:** GitHub Copilot CLI
**Revised:** 2026-05-29 (live session contribution — replaces prior draft)

## Framing note

This seat's angle is developer experience and integration patterns: what does the
flake *actually have to do* to support each tool, does the cost fit the repo's
stated conventions, and what does a consumer config look like after the work
lands? I'll reference specific module and test conventions from this repo rather
than staying at the level of networking theory.

---

## 1. Bottom-line recommendation

**Add `ndppd` as a single, advanced opt-in module. Explicitly exclude
`ndp-proxy-go` and `ndproxy` from the flake boundary. Track `ndpresponder` as a
deferred candidate contingent on nixpkgs packaging.**

The module should be named `services.router-ndp-proxy` and wrap `ndppd` at
launch, with the implementation hidden behind an intent-level API. It must not
be part of `nixosModules.default` (it is not safe to import unconditionally) and
must declare an assertion that blocks silent co-activation with `router-ha`
unless the operator has made an explicit ownership choice — the same pattern BGP
already requires with `ha.singleActiveOwner`.

---

## 2. Strongest case for inclusion

The kernel's built-in `proxy_ndp` sysctl is not a realistic substitute for most
home and small-office router deployments. `systemd-networkd` does expose
`IPv6ProxyNDP = true` and `IPv6ProxyNDPAddress =` entries in `.network` files,
but this only covers addresses that are statically known at network-configuration
time. Any deployment with SLAAC-addressed downstream hosts — which is the
overwhelming majority of home LAN deployments — ends up with a dynamic address
table that static networkd config cannot track.

The concrete deployment that motivates inclusion:

- ISP provides one `/64` via DHCPv6 stateful assignment or SLAAC, without IA_PD
- Router needs to make that prefix reachable to downstream hosts
- Without a proxy daemon, the only options are NAT66 (which abandons real IPv6
  semantics), manual `ip -6 neigh add proxy` per-address (unmanageable under
  SLAAC), or accepting that LAN hosts only get ULA

This scenario is common enough — across European ISPs, cable providers, and
many FTTH deployments — that a flake oriented toward real router deployments
should have an honest answer for it.

`ndppd` is already in `pkgs.ndppd`. It requires no packaging work. Its
configuration surface is narrow. A wrapper that meets this repo's
`module-authoring.md` conventions is achievable in a single focused sprint.
The inclusion cost is real but bounded.

---

## 3. Strongest case against broad inclusion

**Including four tools as equivalent consumer options would expand the support
surface in a way the repo cannot honestly back up, and the HA gap alone is
enough to argue for strict delay on everything except `ndppd`.**

Three specific concerns from a flake-consumer integration perspective:

**The HA assertion problem.** The BGP module blocks eval with a hard assertion
if `router-ha` is present but `ha.singleActiveOwner` is not set:

```
assertion = !routerHaEnabled || cfg.ha.singleActiveOwner;
message = "services.router-bgp with services.router-ha requires explicit
           promotion-aware ownership. Set: services.router-bgp.ha.singleActiveOwner = true;"
```

An NDP proxy module needs an equivalent gate. If both `router` and
`router-backup` run `ndppd` without coordination, they will both answer
Neighbor Solicitations for the proxied addresses. Upstream switches and CPE
devices cache NS/NA entries; a failover that leaves two nodes responding creates
stale cache states that can take 30+ seconds to resolve — long enough to be
operationally significant. The assertion pattern is the right mechanism, but
designing that correctly is non-trivial work that must happen before the module
ships, not after.

**The nixpkgs packaging gap for everything except `ndppd`.** This repo's flake
has a single nixpkgs input and wraps packages that are already in nixpkgs
upstream. `ndpresponder` is not currently in nixpkgs. Wrapping it would require
either adding a custom package derivation inside this flake or adding an
external flake input. Both options create a maintenance burden the repo has so
far avoided: the first means the repo becomes the effective packager; the second
adds a flake lock dependency with its own update cadence and security surface.
Until `ndpresponder` lands in nixpkgs, wrapping it creates coupling that is
inconsistent with the repo's packaging philosophy.

**The `systemd-networkd` native path needs documentation before a daemon.**
If the repo adds an ndppd wrapper without clearly pointing operators toward
`IPv6ProxyNDP` + `IPv6ProxyNDPAddress` for the static-address case, it will
create a support expectation that the daemon is the right answer for all NDP
proxy needs. The daemon should only be recommended after the operator has
consciously rejected the networkd static path. The module docs need to make
this trade-off clear and prominent.

---

## 4. Per-tool assessment

### `ndppd`

**Verdict: Include — as `services.router-ndp-proxy`, advanced opt-in, with
explicit HA assertion.**

`pkgs.ndppd` exists in nixpkgs. The tool is C++ but has a narrow, stable
configuration surface that maps cleanly to a thin declarative wrapper. Upstream
maintenance mode is not a disqualifier here: the project's scope is genuinely
complete (learn NDP neighbors, proxy solicitations between interfaces) and has
not required structural changes to track Linux kernel evolution over the last
several years. The risk profile is similar to `ndppd` being used on stable
kernel releases, which is the repo's deployment target.

Work required before the module meets `module-authoring.md` conventions:
- `modules/router-ndp-proxy.nix` with a narrow option surface (see §5)
- `docs/router-ndp-proxy.md` with options table, minimal example, and an
  explicit "should you use the networkd path instead?" section
- `tests/ndp-proxy-smoke.nix` covering at minimum: standalone eval, eval with
  `router-firewall`, eval with `router-ha` (must fail without HA ownership
  assertion), and a doc-example eval check
- Registration in `flake.nix` as a named module `router-ndp-proxy` but **not**
  in `nixosModules.default` (requiring explicit opt-in)
- An example under `examples/router-ndp-proxy-single-prefix.nix`

### `ndpresponder`

**Verdict: Deferred — do not include until in nixpkgs and a Linux production
use case within the flake's scope is documented.**

The use case is real and distinct from `ndppd`: `ndpresponder` is designed for
the "routed block" pattern where an upstream provider routes a `/64` or `/48`
to your router's WAN address and the router must answer NDP toward the upstream
CPE so the block is reachable. This is the Hetzner/OVH/Equinix Metal pattern
and is common in VPS and dedicated-server deployments.

The blocker is packaging. Adding `ndpresponder` before it is in nixpkgs would
require the repo to:
1. Add a Go package derivation in `pkgs/`
2. Export it from `flake.nix packages`
3. Maintain the derivation against upstream releases independently

That is a qualitatively different maintenance commitment than wrapping an
existing nixpkgs package. The correct trigger for revisiting this decision is
`ndpresponder` appearing in nixpkgs, at which point the wrapper cost becomes
comparable to `ndppd`.

### `ndp-proxy-go`

**Verdict: Exclude — wrong platform target, no Linux production story.**

This tool integrates RA announcements, NDP proxying, and route management in a
way that is specifically designed for FreeBSD's network stack. On Linux the
same concerns are split across `radvd` or `systemd-networkd` RA, kernel
`proxy_ndp`, and the routing table, which `ndp-proxy-go` does not target.
Including this would require claiming Linux support for a tool that its own
upstream does not maintain for Linux. That directly violates the repo's "do not
overclaim maturity" posture, and there is no consumer scenario within this
flake's scope that `ndp-proxy-go` addresses better than the Linux-native tools.

### `ndproxy`

**Verdict: Exclude — the namespace is too fragmented to support honestly.**

"ndproxy" is not a single project. Encountered variants include:
- The FreeBSD kernel knob `net.inet6.ip6.ndproxy_enable` — kernel-level, no
  Linux equivalent under that name
- An old shell-script approach combining `ip -6 neigh add proxy` with
  `ebtables`, found in blog posts from 2010–2016 with no maintained upstream
- Occasional use as a generic label in Linux forum threads referring to whatever
  NDP proxy mechanism is being discussed

There is no `pkgs.ndproxy` in nixpkgs that corresponds to a single maintained
Linux project. The repo cannot write an honest `services.router-ndproxy` module
that documents a stable upstream interface, because the upstream does not exist
as a coherent entity. Including it would mean documenting a label, not a
feature.

---

## 5. Interface recommendation: normalized module vs. raw per-tool wrappers

**Use a normalized `services.router-ndp-proxy` module. Do not expose
per-tool namespaces.**

The reason is the same reason the CLAT module exposes `clatPrefix` and
`v4Address` rather than raw `tayga` config blocks: the consumer's goal is "proxy
NDP dynamically between my upstream interface and downstream LAN segments," not
"configure the ndppd binary." Encoding the tool name into the option namespace
would mean consumer configs need to change if the implementation ever shifts —
for example, if `ndpresponder` becomes the right backend for a routed-block
topology or if a better-maintained Linux tool emerges.

The option surface should be narrow and should match the intent:

```nix
services.router-ndp-proxy = {
  enable = mkEnableOption "dynamic NDP proxy between upstream and downstream segments";

  upstreamInterface = mkOption {
    type = types.str;
    example = "eth0";
    description = "WAN-facing interface. NDP solicitations from the upstream CPE are answered here.";
  };

  downstreamInterfaces = mkOption {
    type = types.listOf types.str;
    example = [ "eth1" "vlan10" ];
    description = "LAN-facing interfaces. NDP entries learned here are proxied upstream.";
  };

  ha = {
    singleActiveOwner = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, the NDP proxy daemon is only started on the VRRP master node.
        Requires services.router-ha.enable = true.
        Must be set explicitly when router-ha is present; the module will not
        eval without this option being set to avoid silent dual-active proxy.
      '';
    };
  };
};
```

The assertion required to enforce HA safety:

```nix
assertions = [
  {
    assertion = !routerHaEnabled || cfg.ha.singleActiveOwner;
    message = ''
      services.router-ndp-proxy with services.router-ha requires explicit
      ownership configuration. Set:
        services.router-ndp-proxy.ha.singleActiveOwner = true;
      This ensures the proxy daemon runs only on the VRRP master and prevents
      both nodes from answering NDP solicitations for proxied addresses.
    '';
  }
  {
    assertion = cfg.ha.singleActiveOwner -> routerHaEnabled;
    message = ''
      services.router-ndp-proxy.ha.singleActiveOwner requires
      services.router-ha.enable = true.
    '';
  }
];
```

The module docs must include a prominent "should you use this?" section that
tells operators to reach for `systemd-networkd IPv6ProxyNDP` + static
`IPv6ProxyNDPAddress` entries first if the downstream address set is bounded
and known. The daemon is only the right answer when addresses are dynamic and
the operator cannot enumerate them at configuration time.

Do not expose a raw `ndppd.conf` passthrough option. Operators who need full
control of `ndppd` configuration should write their own systemd service outside
the wrapper. The module's job is to cover the common case correctly with a
surface that can be maintained forward.

---

## 6. Production-worthiness ranking (Linux/NixOS, this repo's deployment surface)

| Tool | Ranking | Rationale |
|------|---------|-----------|
| `ndppd` | **Moderate** | Field-tested on Linux for 10+ years. Narrow, stable scope reduces regression risk. The main hazard is the HA dual-active scenario, which is fully addressable with the assertion pattern. This repo has handled the same hazard for BGP. |
| `ndpresponder` | **Low–moderate** | Genuinely useful for routed-block VPS/dedicated-server topologies. Go binary, straightforward packaging once it lands in nixpkgs. Linux production story is narrower and less field-tested than `ndppd` at homelab scale. Nixpkgs gap is a real barrier today. |
| `ndp-proxy-go` | **Low (for Linux)** | Not designed for Linux. Its RA+NDP integration model has no clean Linux analogue within this repo's module set. No evidence of production Linux deployments in the router-flake context. |
| `ndproxy` | **N/A** | Cannot rank a fragmented namespace. The question is not "how good is the tool" but "which tool." |

For reference: `systemd-networkd` `IPv6ProxyNDP` + static `IPv6ProxyNDPAddress`
entries rate **moderate–high** for deployments where the proxied address set is
statically bounded. That path should be the documented first recommendation in
`docs/router-ndp-proxy.md` before the daemon wrapper is described.

---

## 7. One-sentence verdict

Add `ndppd` under a normalized `services.router-ndp-proxy` abstraction with a
hard assertion gating co-use with `router-ha`, document the `systemd-networkd`
static path as the first recommendation for bounded address sets, exclude
`ndp-proxy-go` and `ndproxy` entirely, and defer `ndpresponder` until it
appears in nixpkgs — the packaging gap alone disqualifies it from the repo's
current module model.
