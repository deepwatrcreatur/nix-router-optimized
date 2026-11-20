# VyOS Comparison and Gap Analysis

**Status:** comparison and backlog input, not a roadmap. Revision 2
(2026-11-20) applies the review in
[discussion 22](./discussions/22-vyos-parity-plan-review.md). Revision 1
(commit 44992a6) was written by another chatbot and overstated several
points; those are corrected here.
**Target repository:** `nix-router-optimized`
**VyOS versions compared:** 1.4 (LTS) and the 1.5 rolling line. VyOS facts
were checked against upstream docs on 2026-11-20; re-check them before
quoting this page.
**Companion documents:**
- [`FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md)
- [`ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md`](./ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md)
- [`MODULES.md`](./MODULES.md) (56 modules)

Bead router-ytw refreshes this page and the ecosystem feature matrix once
the work items below land.

---

## 1. Summary

VyOS and `nix-router-optimized` both give network engineers a declarative,
auditable router instead of an appliance GUI. They differ in how:

- **VyOS** is a purpose-built network OS on Debian with a hierarchical CLI
  (`set`, `commit`, `save`), image-based upgrades, `commit-confirm`,
  `compare` and `rollback-soft` (rollback without a reboot, 1.4). Its
  configuration is migrated between releases by scripts, which occasionally
  fail on upgrade.
- **`nix-router-optimized`** is a set of typed NixOS modules. Configuration
  is checked at evaluation time (option types and assertions), the system
  builds as one closure, and earlier generations stay available to boot or
  switch back to.

What each side honestly offers:

| | VyOS | `nix-router-optimized` |
| :--- | :--- | :--- |
| **Strengths** | A mature operational CLI; `commit-confirm` and `compare`; a wide protocol set (OSPF, IS-IS, BFD, PIM, IGMP proxy, IPsec, EVPN); conntrack-sync; long production history | Eval-time typing and assertions across all modules; the whole router in one reviewable flake; NixOS VM tests that exercise HA end to end; integrations VyOS doesn't ship (Technitium with zone replication, Kea HA tied to the module system, mesh overlays) |
| **Gaps** | Less composable with a general-purpose OS; LTS images are paid | No automatic revert of a bad change; fewer routing protocols; HA not yet proven on real hardware |

Neither side's rollback is instant. A NixOS rollback (`nixos-rebuild switch
--rollback`, or picking an older generation at boot) needs a path to the
machine. That is exactly what a bad network change can remove, and why
`commit-confirm` matters.

---

## 2. Capability Mapping

Status key: **shipped** (module exists), **VM-tested** (a NixOS VM test
covers it), **gap** (not available).

| Area | VyOS | `nix-router-optimized` | Status |
| :--- | :--- | :--- | :--- |
| Configuration model | Hierarchical CLI tree, migration scripts | Typed Nix modules, eval assertions | Different trade-offs (see §1) |
| Change safety | `commit-confirm`, `compare`, `rollback-soft` | Generations; no auto-revert, no diff preview | **Gap**: router-113 |
| Flow offload | nftables flowtables, software and hardware (1.4) | Software nftables flowtable (`router-firewall.flowtable`, no `flags offload`) | Parity for software offload; hardware offload is a gap (needs NIC support, e.g. mlx5; not the X520) |
| Queueing | Shaper classes, FQ-CoDel, CAKE policy | CAKE (`router-sqm.nix`) | Parity for CAKE |
| VRRP | Keepalived, sync groups, health tracking | Keepalived (`router-ha.nix`): WAN takeover with MAC clone, `preemptDelay`, GARP options, password file | Shipped, VM-tested (`vm-router-ha-wan-failover`, `vm-router-ha-pair`). WAN health tracking (`wan.healthCheck`, router-afb): shipped, VM-tested (`vm-router-ha-wan-health`); no sync group needed (one instance) |
| Stateful failover | conntrack-sync (conntrackd) | None; deferred until VRRP is rehearsed on hardware (discussion 21) | Gap (deferred) |
| DHCPv4 HA | Kea HA (1.5 line) | Kea HA (`router-kea.dhcp4.ha`), port scoped to the peer | Shipped, VM-tested (`vm-router-kea-ha`) |
| DHCPv6 / PD serving | Kea DHCPv6 and PD (1.5 line) | No DHCPv6 server module | **Gap**: router-xm6 |
| Delegated prefix across failover | — | Shared DUID-LL and IAID from the cloned MAC (`router-ha.wan.sharedDhcpIdentity`) | Shipped, VM-tested (`vm-router-ha-wan-failover`; router-5sa) |
| DHCP relay | `service dhcp-relay` | Not exposed (networkd supports `RelayTarget=`) | **Gap**: router-yix |
| Authoritative DNS | Forwarding with authoritative domains | Technitium with TSIG zone replication following VRRP | Shipped, VM-tested (`vm-router-technitium-zone-ha`) |
| BGP | FRR | FRR (`router-bgp.nix`) | Shared engine; compare address families and policy before claiming parity |
| OSPF / IS-IS | FRR | None | Gap (deferred: router-j93) |
| BFD | FRR, tied to routing and VRRP | None; nixpkgs keepalived is built without BFD | Gap (deferred: router-j93) |
| IPsec | Route-based (VTI), policy-based, DMVPN | None (WireGuard, OpenVPN, Tailscale, Headscale, Netbird, ZeroTier, Twingate exist) | Gap: router-3op |
| Multicast | IGMP proxy, PIM | mDNS reflector only (`router-mdns.nix`) | Gap: router-n3i |
| PPPoE client | Yes | `router-pppoe.nix` | Shipped |
| Multi-WAN | WAN load balancing | `router-mwan.nix` | Shipped |
| Zone firewall | Zone-based firewall | `router-zones.nix`, `routerctl firewall explain/trace` | Shipped; UX improvements are docs and `routerctl` work |
| Operational CLI | `show` / `monitor` hierarchy | `routerctl` (status, interfaces, health, diagnostics, firewall, `--json`) | Partial: router-dke adds ha, leases, dns, routes |
| Flow export | Flow accounting | Vector + ulogd NFLOG, ntopng | Different approach; IPFIX deferred |

---

## 3. Work Items

Ordered by the review (discussion 22). HA hardening comes first because the
maintainer's first goal is a safe primary router on elitedesk; the
protocol gaps follow as demand justifies them. Each item lands with docs, an
eval check and a NixOS VM test with a simulated peer, as the repo requires.
No effort estimates: the HA work showed that tests, not the module, set the
pace.

### 3.1 Finish HA hardening

- **router-afb (P1), done: VRRP follows WAN health.**
  `router-ha.wan.healthCheck` makes a master with a dead WAN yield at once
  (FAULT, so the peer's `preemptDelay` does not apply) and pins its priority
  to 1 until `retryAfterSec`. No sync group is needed: there is one VRRP
  instance and the WAN follows it. *Tested:* `vm-router-ha-wan-health`.
- **router-5sa (P1), done: keep the delegated prefix across failover.**
  `router-ha.wan.sharedDhcpIdentity` (default with `clonedMac`) shares a
  DUID-LL and IAID; DAD is off on the cloned-MAC WAN. *Tested:* the same /56
  survives failover and fail-back in `vm-router-ha-wan-failover`.
- **Hardware rehearsal** (nix-clan-homelab nch-sny.36): planned and crash
  failover between elitedesk (X520) and the current router, with timings.

### 3.2 Safe change (router-113, P2)

A confirm-or-revert apply: switch, then return to the previous generation
unless confirmed within N seconds, plus a preview of the effective change
(closure diff and rendered nftables, keepalived, Kea and networkd diff).
*Test:* a change that breaks management access, left unconfirmed, is
reverted within the timeout.

### 3.3 Extend `routerctl` (router-dke, P2)

The revision-1 plan proposed a new `router-cli`. `routerctl` already exists
(`pkgs/router-diag`), so it gains subcommands instead, each with stable
`--json` and explicit "unavailable" states:

```bash
routerctl ha       # role from /run/router-ha/role, keepalived and Kea HA state
routerctl leases   # Kea DHCPv4 leases via /run/kea/dhcp4.sock
routerctl dns      # Technitium zone types and sync state (API, .status checked)
routerctl routes   # kernel FIB plus FRR (vtysh JSON)
```

*Test:* JSON shape asserted inside an existing two-router VM test.

### 3.4 Common edge needs (P3)

- **router-yix: DHCP relay and option 82.** Wrap systemd-networkd's
  `[DHCPServer]` `RelayTarget=`, `RelayAgentCircuitId=` and
  `RelayAgentRemoteId=`; no new daemon. *Test:* client, relay and DHCP
  server VMs.
- **router-xm6: DHCPv6 and PD serving.** First document what networkd
  already provides (RA, DHCPv6 server, sub-delegation of the ISP prefix),
  then decide whether a module is needed.

### 3.5 Routed multicast (router-n3i, P3, after HA)

`igmpproxy` by default (proxy semantics suit IPTV), `smcroute` only for
static cross-VLAN routes; neither has a NixOS module yet.

- The upstream is a configurable interface, often an ISP IPTV VLAN, not
  assumed to be the WAN.
- nftables allows IGMP on the upstream and forwards `224.0.0.0/4` only to
  listed downstreams; `rp_filter` is handled.
- The docs make no ISP-specific promises. IPTV services vary (VLAN, 802.1p
  priority, DHCP options, IGMPv3/SSM), and `quickleave` can interrupt other
  viewers.
- Discovery protocols for Sonos-style devices are SSDP/mDNS, handled by
  reflection rather than multicast routing.

*Test:* an upstream source and querier VM; a downstream receiver joins,
receives, stops after leaving; another VLAN never receives.

### 3.6 Route-based IPsec (router-3op, P4)

Use the nixpkgs `strongswan-swanctl` module with **XFRM interfaces**
(networkd `Kind=xfrm`, `if_id`), not VTI.

- Credentials come from files.
- IKE (UDP 500/4500) and ESP are allowed only on the WAN and only for
  configured peers.
- Tunnel interfaces go into an explicit `router-zones` zone.
- BGP over the tunnel is optional, through `router-bgp`.

Clouds don't all require route-based IPsec: AWS and Classic Google Cloud VPN
also allow static routing, and Azure offers policy-based gateways. BGP over
a route-based tunnel is the common and most flexible case. SAs re-establish
after a VRRP failover (there is no SA sync), and the interaction with
flowtable offload needs checking. *Test:* against a strongSwan peer VM, the
SA is established, ping passes through the XFRM interface, BGP is
Established and nothing falls back to cleartext.

### 3.7 Deferred and rejected

- **OSPF and BFD (router-j93, deferred).**
  - OSPF is a thin layer over `services.frr`, but neither goal needs it
    until there's an L3 peer.
  - BFD detection time is the multiplier times the negotiated interval:
    300 ms x 3 is about 900 ms before reconvergence starts.
  - On a single segment, VRRP adverts already fail over in seconds.
  - VRRP-driven BFD needs a keepalived build with `--enable-bfd`.
- **EVPN/VXLAN: rejected** for an edge-router flake.
- **NetFlow/IPFIX: deferred.** `router-observability` (Vector, ulogd) and
  `router-ntopng` cover flow visibility. An exporter would have to account
  for flows that the flowtable offloads past netfilter.
- **conntrack-sync: deferred** until plain VRRP failover is rehearsed on
  hardware (discussion 21).

---

## 4. Revision 1 errors corrected here

For readers comparing revisions:

- **VyOS does have flowtable offload and CAKE.** Revision 1 called its
  flowtables experimental and listed CAKE as a NixOS advantage, although its
  own table listed CAKE for VyOS.
- **router-ha does not use conntrackd.** Revision 1 rated HA "Parity+".
- **`routerctl` already exists**, so no new CLI was needed.
- **Paths:** the Kea socket is `/run/kea/dhcp4.sock`, the HA role is in
  `/run/router-ha/role`, and the WAN option is `wan.device`.
- **There is no DHCPv6 server**, so `router leases` couldn't have shown
  DHCPv6 leases.
- **Rollback:** "sub-second bootloader rollback" and "zero runtime drift"
  overstated both.
- **BFD:** "microsecond heartbeats" and "<300 ms" are wrong (see §3.7).
- **Cloud IPsec:** "clouds mandate route-based IPsec" is wrong (see §3.6).
- **IPTV:** the "freezes after 5-10 seconds" symptom was unsourced.
- **Effort estimates** of 2-5 days per item were removed.
