# Discussion 03: Router-Backup Standby and Shared-WAN Failure Mode

**Status:** closed
**Opened:** 2026-05-09
**Participants requested:** DeepSeek, Gemini, GitHub Copilot, Codex

## Relevant prior notes

From [docs/incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md](../incidents/2026-04-23-dhcp-vrrp-regression/SUMMARY.md):

- The earlier HA/VRRP outage was not a single bug. It involved Kea runtime shape,
  HA control-plane reachability, missing HA hook support, and deployment
  divergence between `router` and `router-backup`.
- The staged production design used per-node LAN HA addresses
  (`10.10.10.2`, `10.10.10.3`) plus a backup-only carrier guard.
- The incident closed with the understanding that the live pair was not yet in a
  verified common HA state.

From [modules/router-ha.nix](../../modules/router-ha.nix):

- VRRP is implemented with Keepalived.
- When `services.router-ha.wan.enable = true`, Keepalived notify hooks:
  - set a cloned WAN MAC on master transition
  - bring WAN up on master transition
  - bring WAN down on backup/fault transition
- This means WAN behavior is currently coupled to Keepalived state transitions.

## Fresh facts from 2026-05-09

1. `router-backup` has been rewired and reconfigured to use:
   - `ens18` = management
   - `ens19` = LAN
   - `ens27` = WAN
2. `router-backup` management has been restored to `192.168.100.99/24`.
3. Extra `iot`/`guest` VLAN interfaces were removed from intended standby
   config; they should not be part of the default backup stance.
4. When `router-backup` WAN was connected to an unmanaged switch that also
   connects the modem and primary router WAN, the live primary router WAN
   flapped and family internet connectivity was disrupted.
5. The user then observed a stronger result: even with `router-backup` WAN
   disconnected, bringing `router-backup` up still disrupted connectivity,
   and shutting `router-backup` down restored it.
6. That suggests the current failure mode is not just shared-WAN MAC conflict.
   It may also involve LAN-side duplicate-router behavior during supposed
   standby.

## Question for this round

Given the above, what should the **standby design** be in `nix-router-optimized`
before any future HA/VRRP attempt?

Please answer concretely:

1. Should `router-backup` in standby keep **management only**, with both LAN and
   WAN administratively inactive?
2. If not, which services or identities must be disabled while standby is not
   promoted?
   - VRRP
   - Kea
   - UPnP / NAT-PMP
   - DNS / Technitium
   - LAN address ownership
   - cloned WAN MAC
3. Does the current `router-ha` design couple too much behavior into
   Keepalived notify hooks?
4. Is the unmanaged shared-WAN switch topology acceptable later, or should the
   design assume something stricter before re-enabling HA?
5. What should be the next safe implementation step in the flake?

## Response format

- Start with one sentence naming your core recommendation.
- Then give:
  - `Standby policy:`
  - `Why the current design fails:`
  - `Next safe step:`
- End with one of:
  - `[satisfied]`
  - `[satisfied-conditional: ...]`
  - `[needs more evidence: ...]`

## Round 1 highlights

### DeepSeek

- Core recommendation: strict **management-only** standby.
- Standby should keep `ens18` only, with `ens19` and `ens27` administratively
  down until explicit promotion.
- Disable or management-bind all router identity on the backup:
  VRRP, Kea, UPnP, DNS, VIP ownership, cloned WAN MAC.
- Main diagnosis: the current design still lets the backup emit router behavior
  on LAN/WAN, and Keepalived notify hooks are too broad a control surface.
- Status: `[satisfied-conditional: validate by repeated boot/shutdown tests]`

### Codex

- Core recommendation: make `router-backup` a **management-only cold standby**
  by default.
- Treat LAN/WAN participation as an explicit promotion/test mode, not default
  standby behavior.
- Disable VRRP, Kea, UPnP, DNS/Technitium, LAN VIP ownership, and cloned WAN
  MAC while in standby.
- Main diagnosis: the current `router-ha` module only gates WAN behavior, not
  full router identity; backup can still interfere on LAN.
- Status: `[satisfied]`

### GitHub Copilot

- Core recommendation: keep **management-only** standby and administratively
  disable both LAN and WAN until promotion.
- Similar diagnosis: standby currently runs too much active router behavior and
  the unmanaged shared-WAN topology is unsafe.
- Status: `[needs more evidence: confirm precise LAN disruption root cause]`

### Gemini

- Core recommendation: adopt a **warm standby** policy, but only if every node
  has a unique LAN identity and high-impact services are tightly gated.
- Gemini agrees the current design fails because standby still behaves like a
  live router on LAN/WAN.
- The key divergence is that Gemini does **not** insist on keeping LAN fully
  down by default; it argues that a unique per-node LAN IP plus service gating
  could be safe enough for a warmer standby.
- Status: `[satisfied]`

## Round 2 question

Round 1 converged on the diagnosis that the current standby model is unsafe,
but there is a strategic disagreement:

- **Cold standby**: management only; LAN and WAN both inactive until promotion.
- **Warm standby**: management active, unique per-node LAN identity allowed,
  but router services/VIP/WAN tightly gated until promotion.

For round 2, answer only this:

1. Which default should `nix-router-optimized` ship **now**: cold standby or
   warm standby?
2. If warm standby is still worth preserving later, should it be:
   - the default, or
   - an explicit advanced mode layered on top of cold standby?
3. Is there any condition under which keeping LAN up by default on the backup
   is defensible **before** WAN HA is revalidated?

Keep the answer short:

- `Default now:`
- `Future advanced mode:`
- `LAN-up before WAN revalidation?:`
- final status marker

## Fresh facts from 2026-05-09 (consumer-state audit)

The upstream HA discussion now needs one more decision layer: not just **what**
standby policy we want, but **where** the active-router identity is currently
coming from and what must be split before another HA retest is meaningful.

From `unified-nix-configuration`:

1. `router-backup` still imports the active router's shared service modules:
   - `den/hosts/router-backup/default.nix`
     - imports `hosts/nixos/router/networking.nix`
     - imports `hosts/nixos/router/caddy.nix`
2. Those shared imports still enable active router services by default:
   - `hosts/nixos/router/networking.nix`
     - `services.router-dns-service.enable = true`
     - `services.router-kea.enable = true`
     - `services.router-ntp.enable = true`
     - `services.router-upnp.enable = true`
   - `hosts/nixos/router/caddy.nix`
     - `services.caddy.enable = true`
     - public-facing reverse proxy / DDNS wiring is shared with `router-backup`
3. The consumer HA wiring is still management-plane oriented:
   - `hosts/nixos/router/role.nix`
     - `services.router-ha.keaSync.peerAddress` still uses management IPs
     - `services.router-kea.dhcp4.ha.peerAddress` still uses management IPs
     - consumer config does not yet set `services.router-kea.dhcp4.ha.localAddress`
4. So the current practical problem is bigger than Keepalived alone:
   `router-backup` still boots much of the active router service identity unless
   something outside this consumer tree disables it later.

## Round 3 question

Given the above, answer this as an **implementation-order** round:

1. Before any more HA/VRRP retesting, should the first change be to split the
   current router profile into:
   - a **base router platform** shared by `router` and `router-backup`
   - an **active router services** layer enabled only on the promoted node?
2. For a default **cold standby** profile, which of these must be absent by
   default on `router-backup`, not merely "configured but idle"?
   - Caddy / DDNS
   - DNS / Technitium
   - Kea DHCP / DHCP-DDNS
   - UPnP / NAT-PMP
   - NTP service to LAN
   - VRRP / Keepalived
   - WAN interface activation / cloned MAC
3. Where should the standby policy live first?
   - primarily in `nix-router-optimized`
   - primarily in `unified-nix-configuration`
   - or in both, with upstream module affordances plus consumer policy wiring?
4. What should be the first implementation PR after this discussion?
   - split shared imports / profiles
   - rewire Kea HA to LAN-plane `localAddress` / `peerAddress`
   - add the backup carrier guard
   - something else, but still preserving a safe standby default

Keep the answer short:

- `First structural change:`
- `Cold-standby service boundary:`
- `Policy ownership:`
- `First implementation PR:`
- final status marker

### GitHub Copilot

- `First structural change:` Yes: split the current shared router profile into a
  base platform and an active-router-services layer before any more HA/VRRP
  retesting. Right now `router-backup` still inherits too much active identity
  from consumer imports, so further HA tests would keep mixing policy errors
  with protocol behavior.
- `Cold-standby service boundary:` For the default standby profile, these should
  be absent on `router-backup` by default: Caddy/DDNS, DNS/Technitium, Kea
  DHCP/DHCP-DDNS, UPnP/NAT-PMP, LAN-facing NTP, VRRP/Keepalived participation,
  and WAN activation / cloned MAC. Management access, observability, and
  explicit recovery tooling can stay.
- `Policy ownership:` Both. `nix-router-optimized` should expose the right
  affordances and safe defaults for standby/promoted behavior, while
  `unified-nix-configuration` should own the concrete host policy and import
  split.
- `First implementation PR:` Split shared imports / profiles first. After the
  backup is truly cold by default, follow with LAN-plane Kea HA
  `localAddress`/`peerAddress` wiring and the backup carrier guard.
- `[satisfied]`

## Post-round correction from live recovery work (2026-05-09)

The earlier "cold standby" framing is too narrow for the actual goal.

The intended design is that if `router` fails, `router-backup` must be able to
provide the router's full service set, not merely management access plus manual
recovery tools. That changes the design target from "remove services from the
backup" to "make service ownership promote safely without split-brain."

So the more accurate structural split is:

1. **Shared router capability layer**
   - both nodes can run the router stack
   - both nodes have the service definitions, packages, and base configuration
     needed for DHCP, DNS, NTP, Caddy/DDNS, UPnP/NAT-PMP, firewalling, and WAN
     routing
2. **Active ownership / promotion layer**
   - only the promoted node owns the active identity:
     - VRRP VIPs
     - WAN carrier / cloned MAC behavior
     - LAN service binding / advertisement
     - any public-facing DDNS / reverse-proxy identity
     - write-active roles such as lease/DDNS primacy

That means the first structural change is still a split, but not into "base
router" versus "services absent on backup." It should instead become:

- a **shared capability profile** that makes both nodes failover-capable
- an **active-identity / promoted-owner layer** that prevents both nodes from
  acting live at the same time

### Real CLI follow-up

#### Gemini CLI

- `First structural change:` Decouple the router profile into a shared
  "base-platform" and an "active-services" layer enabled conditionally via
  role-based imports.
- `Cold-standby service boundary:` Caddy/DDNS, DNS/Technitium, Kea
  DHCP/DHCP-DDNS, UPnP/NAT-PMP, and WAN activation/cloned MAC must be absent to
  prevent split-brain identity and MAC/IP conflicts.
- `Policy ownership:` Both; `nix-router-optimized` for module-level state
  abstractions and `unified-nix-configuration` for host-specific role
  assignment and VRRP priority.
- `First implementation PR:` Split shared imports and profiles into core
  platform and service-identity layers.
- `[satisfied]`

#### Codex CLI

- `First structural change:` Split the router profile into a shared base
  platform and an `active-router-services` layer enabled only on the promoted
  node before more HA/VRRP retesting.
- `Cold-standby service boundary:` Must be absent by default on
  `router-backup`: `Caddy/DDNS`, `DNS/Technitium`, `Kea DHCP/DHCP-DDNS`,
  `UPnP/NAT-PMP`, and `NTP service to LAN`. From the stated facts alone,
  `VRRP/Keepalived` and `WAN activation/cloned MAC` are not established as the
  first must-absent set.
- `Policy ownership:` `nix-router-optimized` first.
- `First implementation PR:` Split the shared imports / profiles so
  `router-backup` stops inheriting active-router service modules by default;
  rewire `Kea` HA and add carrier/WAN guards after that boundary exists.
- `[satisfied]`

### Incorporating Discussion 04: security/zones recovery review

Discussion 04 changes how aggressive we should be about the first HA refactor.

The recovered `router-security-hardened` / `router-zones` work is not
merge-ready yet:

- `router-zones` can render invalid nftables output in at least one default path
- input-path semantics are incomplete or misleading
- Geo-IP scope and transport are not yet safe enough to trust as a release
  firewall control

That matters here because failover design should not assume those recovered
security modules are ready to become part of the promotion boundary.

So for HA purposes:

1. The **promotion split should be defined around already-understood router
   identity and service ownership**, not around the recovered security/zones
   modules yet.
2. The `router-firewall` extension seam remains useful, but any future
   zone-aware or hardened policy must be:
   - semantically correct for router-local input versus forwarded traffic
   - rendered safely
   - validated against the promoted-node failover path
3. The first HA implementation PR should avoid coupling itself to the unmerged
   security/zones feature set.

### Updated synthesis

- `Design target:` Full-service failover with single active owner, not cold
  standby with reduced services.
- `First structural change:` Split shared capability from active identity /
  promotion gating.
- `First implementation PR:` Split shared imports / profiles so both nodes can
  be failover-capable while only the promoted node owns live router identity.
- `Follow-up after split:` Rewire Kea HA to LAN-plane
  `localAddress`/`peerAddress`, then add backup carrier/WAN ownership guards.
- `Security/zones note:` Keep Discussion 04 work out of the first HA split until
  nft rendering and input-path semantics are repaired.

**Closure status:** Closed. The preserved conclusion is that HA work should
first split shared failover-capable router capability from active identity /
promotion ownership, rather than treating `router-backup` as a permanently
reduced cold-standby node.
