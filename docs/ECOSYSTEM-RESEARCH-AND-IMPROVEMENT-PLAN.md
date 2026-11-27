# NixOS Router Ecosystem Research & Architectural Improvement Plan

**Status**: Research & Strategic Architecture  
**Target Repository**: `nix-router-optimized`  
**Homelab Consumers Analyzed**: `router` (Primary, Proxmox VM / igc 2.5G) and `elitedesk` (Standby, HP EliteDesk 8300 SFF / X520 10G SFP+)  
**Infrastructure Context**: Migration from `unified-nix-configuration` to `nix-clan-homelab` (Clan-core, Den aspects, `clan vars`, `deploy-rs`)  
**Date**: November 2026 (revision 1)  
**Revised**: 2026-11-19 (revision 2: panel review, see §0); 2026-11-21 (revision 3: shipped work, see §0.2.1); 2026-11-25 (revision 4: HA prior art, see §0.1); 2026-11-27 (revision 5: VRRP live on hardware, how the project compares, see §0.2.2–§0.2.3)  

---

## 0. Revision 2 (2026-11-19): project state and review findings

**This section is authoritative.** Where §1–§7 (revision 1) disagree with it, this
section wins. Future agents should read §0 first, then
[discussion 21](discussions/21-ecosystem-plan-review.md) for the reasoning, and
the beads queues for live status. §1–§7 are kept as the original research
input, with factual errors corrected in place (marked *[rev 2]*).

### 0.1 Revision history

| Revision | Date | Author | Change |
| --- | --- | --- | --- |
| 1 | 2026-11 | external chatbot | Original research, survey and proposals |
| 2 | 2026-11-19 | Claude (IC), after a five-voice panel (Codex, Gemini, Claude, Copilot, DeepSeek) | State of the project; priorities and verdicts from discussion 21; factual corrections |
| 3 | 2026-11-21 | Claude (bead router-ytw) | §0.2.1 lists what shipped in #153–#174; stale items in §0.2–§0.3 and the feature matrix are marked *[rev 3]* |
| 4 | 2026-11-25 | Claude | Single-WAN-address HA prior art (OPNsense, NethSecurity, VyOS, Kea) and the decisions it led to: [`router-ha-prior-art.md`](./router-ha-prior-art.md); pointer added in §3.5 |
| 5 | 2026-11-27 | Claude | §0.2.2 lists #177–#198 and the live VRRP pair with measured drills; §0.2.3 compares the project with OPNsense, VyOS and the Nix router projects as of today; stale statements in §0.2 and the §3 matrix are marked *[rev 5]* |

### 0.2 State of the project as of 2026-11-19

**Shipped in nix-router-optimized** (PR numbers):

- `router-ha.preemptDelay`: delayed fail-back (#144). The dashboard no longer
  requires `/run/agenix` (#144).
- `router-technitium.zoneReplication`: TSIG AXFR/IXFR and NOTIFY to standbys
  (#145).
- `zoneReplication.ha`: zones follow VRRP. The owner unit is single-active;
  demotion is guarded (SOA from another node, validated export, MASTER
  re-check, lock), and a reconcile timer handles reboots (#148, #149).
- `router-alerting`: Alertmanager plus an ntfy relay, email, webhooks and
  native receivers, a healthchecks-style watchdog, and new-DHCP-device
  notices via Kea `run_script` (#150). Every alert names its host (#152).
- `router-homelab` dashboard links never use a wildcard address (#146).
- From discussion 20: topology assertions, the hardware safety matrix,
  multi-node VM test harness, `routerctl` diagnostics, systemd slice
  isolation (beads `router-a2z`, `router-inl`, `router-osv`, `router-tat`,
  `router-qmu`, all closed).

#### 0.2.1 Shipped since revision 2 (as of 2026-11-21)

Every item has a NixOS VM test unless noted. The test names are flake checks
(`nix build .#checks.x86_64-linux.<name>`).

| Area | What shipped | PR | Proof |
| --- | --- | --- | --- |
| VRRP secret | `router-ha.vrrpPasswordFile` via a systemd credential; no default password, no store copy | #153 | eval checks |
| GARP/NA refresh | keepalived gratuitous ARP and NA options | #154 | eval checks |
| WAN promotion | `networkctl` up/reconfigure instead of restarting systemd-networkd | #155 | `vm-router-ha-wan-failover` |
| DHCPv4 HA | Kea HA made real; HA port scoped to the peer; `keaSync` retired | #156 | `vm-router-kea-ha` |
| VRRP lifecycle | crash, FAULT on LAN loss, reboot, `preemptDelay`, single-active units | #158 | `vm-router-ha-pair` |
| Zone ownership | Technitium zones follow VRRP; NOTIFY from HA peers | #159 | `vm-router-technitium-zone-ha` |
| WAN health | a master with a dark WAN yields at once (FAULT), then pins its priority; interval headroom | #161, #174 | `vm-router-ha-wan-health` |
| Prefix across failover | shared DUID-LL/IAID keeps the delegated prefix | #162 | `vm-router-ha-wan-failover` |
| Operations | `routerctl ha/leases/dns/routes` with `--json` | #163 | JSON asserted in `vm-router-kea-ha`, `vm-router-technitium-zone-ha` |
| Safe change | `router-apply` switch/confirm/diff with auto-revert | #164 | `vm-router-apply` |
| Single-active services | RA owner, DDNS, UPnP and Kea D2 follow VRRP | #166 | `vm-router-ha-pair`, eval checks |
| DHCP relay | `router-dhcp-relay` with option 82 | #167 | `vm-router-dhcp-relay` |
| Downstream IPv6 | SLAAC from the delegation, `ipv6SubnetId`; DHCPv6/PD serving decided against for now | #168 | `vm-router-ipv6-downstream` |
| Multicast | `router-multicast` (igmpproxy) for IPTV | #169 | `vm-router-multicast` |
| IPsec | `router-ipsec` (strongSwan swanctl, XFRM interfaces); router-bgp policy rendering fixed | #170 | `vm-router-ipsec` |
| Dashboard | API listen backlog 5 → 128 | #171 | — |

Still true: VRRP is not enabled on the homelab pair, and there has been no
live failover on hardware (`nch-sny.36`). *[rev 5: no longer true; the pair
has run VRRP since 2026-11-25 and passed power-cut drills, see §0.2.2.]*

#### 0.2.2 Shipped since revision 3, and the live pair (as of 2026-11-27)

| Area | What shipped | PR | Proof |
| --- | --- | --- | --- |
| Observability | `enableVector` follows the ulogd output plugin | #177 | eval checks |
| Secrets | `*File` secret options, so modules work without agenix | #178 | `router-secret-files` eval checks |
| DNS | SSH client entries in generated zones are opt-in per host | #181 | `dns-zone-ssh` eval checks |
| Pangolin | Pangolin 1.24's AI gateway moved off `internal_port` | #183 | eval check |
| HA research | Prior art for one dynamic WAN address (OPNsense, NethSecurity, VyOS, Kea) | #184 | [`router-ha-prior-art.md`](./router-ha-prior-art.md) |
| DHCPv4 HA | Kea `dhcp4.ha.mode = "hot-standby"` | #185 | `vm-router-kea-ha-hot-standby` |
| VRRP transitions | Applied in order through keepalived's `notify_fifo`; reload mid-promotion finishes it | #186 | `vm-router-ha-pair` |
| WAN lease | Demotion sends the ISP no DHCP RELEASE; WAN DHCP clients never send one (`SendRelease=no`) | #187, #189 | `vm-router-ha-wan-failover` |
| DNS zones | Static sync leaves Secondary and VRRP-owned zones to their owner | #188 | `vm-router-technitium-zone-ha` |
| Hardening | Configurable `rp_filter`, stronger module blocking | #191 | `vm-router-security-hardened` |
| Tailscale | `tailscaled-autoconnect` retries after a start timeout | #192 | doc example check |
| IPv6 failover | The MASTER sends RAs from a virtual link-local (`fe80::1`, RFC 5798 style), so a dead MASTER leaves clients no stale default route | #193 | `vm-router-ha-pair` ("MASTER power loss") |
| Fail-back hold | `peerWaitSec`: keepalived's start waits for the peer's advert, so a late-forwarding switch port cannot bypass `preemptDelay` | #196 | `vm-router-ha-pair` ("late LAN forwarding"), mutation-checked |
| VRRP transport | `unicastPeers`/`unicastSrcIp` for LANs that drop VRRP multicast; validated addresses; VRRP firewall rule covers IPv6 | #197 | `vm-router-ha-pair` runs on unicast with multicast dropped, mutation-checked |
| Pangolin | gerbil ≥ 1.5.2 so a stop no longer panics and fails the unit on every demotion | #198 (open) | `router-pangolin-etc-dir-eval` |

The flake now has 382 checks, 14 of them NixOS VM tests.

**The homelab pair is live** (nix-clan-homelab `nch-sny.36`):

- VRRP since 2026-11-25: `elitedesk` (bare metal, ConnectX-4 Lx, priority
  110) and `router` (bare metal, igc, priority 100), `preemptDelay` 300 s,
  Kea hot-standby, Technitium zones following VRRP, WAN health tracking.
- Drills, 2026-11-26 and 2026-11-27: cable pulls, `keepalived` stops and
  power cuts of the MASTER. The ISP kept the IPv4 lease and the /56 in every
  step.
- Power cut of the MASTER on 2026-11-27 (after #193, #196, #197): the
  BACKUP took over with the gateway back in 2.2 s, IPv6 in 5.7 s, IPv4 in
  9.4 s. The rebooted preferred node heard its peer 8 s after LAN carrier,
  started as BACKUP and took the gateway back after the full 300 s, with
  1.3 s of IPv4 and 0.3 s of IPv6 loss. Clients kept `fe80::1` as their IPv6
  router throughout.
- Operations around the pair (nix-clan-homelab): `fleet-deploy` with a
  post-deploy health check and deploy-rs magic rollback, `fleet-status` for
  hosts that lag `main`, one inventory as the source for host and router
  metadata (#85), and fleet alerting through the routers' clustered
  Alertmanagers (#96, decision 0005).
- What the drills found that the VM tests had not: a deploy's networkd
  reconfigure sent DHCP RELEASE and renumbered the /56 (#189); a dead
  MASTER's RA route lingered on clients (#193); a switch between the nodes
  dropped VRRP multicast one way, so the preferred node took over 3 s after
  every start (#196, #197); a deploy over the management address cut its own
  SSH session when the VIP moved (nix-clan-homelab #102).

#### 0.2.3 How the project compares (2026-11-27)

This compares what each project does for a home or small-office edge router.
Facts about other projects come from their documentation and from
[`router-ha-prior-art.md`](./router-ha-prior-art.md) and
[`FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md); no
throughput benchmarks have been run, so none are claimed.

| Concern | `nix-router-optimized` | OPNsense | VyOS | Nix router repos (§3) |
| --- | --- | --- | --- | --- |
| Configuration | Nix modules; whole system built from one expression, atomic switch, boot-menu rollback, `router-apply` auto-revert | Web GUI over `config.xml`; imperative upgrades | CLI with commit/rollback of its config tree | Nix modules |
| Gateway redundancy | VRRP (keepalived), multicast or unicast, tested on two nodes and drilled on hardware | CARP, built in | VRRP, built in | none |
| One DHCP-assigned WAN address shared by two nodes | Built in: WAN raised only on the MASTER with a cloned MAC and shared DHCP identity, no RELEASE, WAN health yield; lease and /56 kept in live drills | Community hook script or plugin; reported to break across upgrades | Transition scripts written by the operator | none |
| IPv6 RAs across failover | Virtual link-local router address that moves with the MASTER | not covered by the sources read | not covered by the sources read | none |
| Fail-back control | `preemptDelay` plus a start gate that waits for the peer | CARP advskew/preempt | `preempt-delay` | none |
| Connection state sync | **none** (conntrackd deferred); established flows through NAT reset on failover | pfsync, built in | conntrack-sync | none |
| DHCP server HA | Kea HA, hot-standby or load-balancing | Kea HA available; forum reports of instability after upgrades | DHCPv6 server not supported with HA (1.4, forum) | none |
| Services that must run on one node | Typed single-active ownership (DDNS, UPnP, RAs, Kea D2, DNS zones, any unit) | per-service, mostly manual | transition scripts | none |
| Config sync between nodes | not needed: both nodes build from the same expression | XMLRPC sync from the primary | config-sync (manual or scripted) | n/a |
| Monitoring and alerting | Prometheus, Grafana, Netdata, Vector/ulogd; Alertmanager with ntfy, email and webhooks plus a healthchecks watchdog (`router-alerting`). In the homelab (nix-clan-homelab #96) both routers also scrape every other host, alert on failed units, disks (SMART) and certificate expiry, and cluster their Alertmanagers across the VRRP pair | RRD graphs and Monit, built in | Prometheus exporters and Telegraf as services | Vector/ulogd (joshpearce) |
| Web UI | read-mostly dashboard plus `routerctl`; no configuration through the browser | full configuration GUI | none by default | mostly none |
| Breadth | 56 modules (VPNs, IPsec, BGP, multi-WAN, SQM, DNS, IDS hooks, tunnels) | large plugin catalogue | broad routing feature set | narrow |
| Automated tests | 14 NixOS VM tests (most multi-node) and 368 eval checks in CI | project CI | smoketests | few |
| Who it suits | someone who already runs NixOS and wants the router in the same repository | anyone who wants an appliance with a GUI | network engineers who want a router OS with a CLI | their authors |

**Where it leads:** reproducible whole-system builds and rollback; HA for the
common residential case of one dynamic WAN address, which OPNsense and VyOS
leave to community scripts; IPv6 RA failover; typed single-active services;
HA behaviour checked by multi-node VM tests and live drills; and, in a fleet
built with Nix, the router pair doubling as the redundant alerting hub for
every other host, configured from the same inventory.

**Where it trails:**

- No connection-state sync. Flows through NAT reset on failover; OPNsense
  (pfsync) and VyOS (conntrack-sync) keep them.
- No configuration GUI and a steep entry cost: Nix, flakes and a secret
  manager are prerequisites.
- One operator and one homelab pair as the only production deployment, so
  ISP and switch variety are barely sampled (the VRRP-multicast switch
  problem was found only in the 2026-11-27 drill).
- Changing VRRP transport or restarting keepalived on the MASTER costs a
  gateway outage (145 s during the unicast rollout, before
  nix-clan-homelab #101 raised the deploy-rs activation timeout).

**Not done** *[rev 3: the three items below were fixed in #156, #155 and #153]*:

- VRRP is **not** enabled on the homelab pair. There has been **no** live
  failover; the zone promotion and demotion was rehearsed by hand on elitedesk.
- DHCP is single-active with manual promotion. The `keaSync` option in
  `router-ha` contradicts that model (bead `router-4dk`).
- `notify_master` still restarts systemd-networkd (`modules/router-ha.nix`,
  bead `router-53n`).
- The VRRP password defaults to `nix-router-ha` and lands in the Nix store
  (bead `router-ehu`).

**Homelab consumers:** *[rev 5: stale. `router` is now bare metal and a
clan-managed VRRP member (priority 100); `elitedesk` runs a ConnectX-4 Lx
and is the preferred VRRP member (priority 110); see §0.2.2.]*

- `router`, the primary, is a Proxmox VM managed by
  unified-nix-configuration.
  - It uses passed-through Intel igc ports for LAN (`enp6s16`) and WAN
    (`enp6s17`), both 2.5 Gb/s, with e1000e for management (`ens18`).
  - It already uses `zoneReplication.primary` and the upstream RFC2136 unit.
- `elitedesk`, the standby, is bare metal managed by nix-clan-homelab (Clan
  and den).
  - Its NIC is an Intel X520 (ixgbe) on 10G DAC.
  - Its WAN is administratively down.
  - It holds the zones under `zoneReplication.ha` and runs router-alerting
    (ntfy and the watchdog).

**Open incidents:**

- [`incidents/2026-11-19-x520-tcp-reply-loss`](incidents/2026-11-19-x520-tcp-reply-loss/SUMMARY.md):
  1–8% of TCP connections to elitedesk lost every SYN-ACK at the X520, while
  UDP was unaffected.
  - With Flow Director ATR off (`ntuple on`), 0 of 6920 TCP queries failed
    over 2 h.
  - An ATR-on control is running.
  - *[rev 3: elitedesk now runs the ConnectX-4 Lx; its 24 h gate is in progress.]*
- The same card once dropped off the PCIe bus (homelab bead `nch-sny.31`).
- Together they **gate any promotion of elitedesk**: a 24 h pass/fail
  threshold (`nch-sny.34`). A Mellanox ConnectX-4 Lx is available as the
  replacement.

### 0.3 Priorities (replaces §4's P1–P4 ordering and §6's roadmap)

| Order | Work | Beads |
| --- | --- | --- |
| P0 | Hardware gate: close the X520 incident against its threshold, add AER and link-flap alerting, or swap the NIC | `nch-sny.34`, `nch-sny.31` |
| P1 | Failover correctness: WAN promotion without restarting networkd; two-node VRRP VM test (promote, demote, fault, reboot, zone HA, single-active units); VRRP secret as a file *[rev 3: done, #153, #155, #158, #159]* | `router-53n`, `router-0lh`, `router-ehu` |
| P1 | Supervised failover rehearsal with measured outage and tested fail-back, before VRRP is enabled | `nch-sny.36` |
| P2 | Typed per-service single-active ownership, and one DHCP HA model (`keaSync` retired or made real) *[rev 3: done, #156, #166]* | `router-4dk`, `router-d9g` |
| P2 | Dashboard listen backlog (5 → larger); fix the doc errors in this file *[rev 3: done, #171]* | `nch-sny.35`, `router-q5k` |
| P3 | Keepalived's built-in GARP and NA refresh options *[rev 3: done, #154]* | `router-3m7` |
| Later | conntrackd, IRQ/RPS/XPS tuning, automatic CAKE, SSE, netns, CoreRAD (see 0.4) | none yet |

The panel was unanimous: hardware validation and plain failover correctness
come before session preservation or performance work. New proposals feed
discussion 20's roadmap instead of competing with it.

### 0.4 Verdicts on the §4 proposals

| Proposal (§) | Verdict | Condition or reason |
| --- | --- | --- |
| Node role modeling (4.1.1) | adopt, modified | Typed per-service ownership tied to the VRRP state (the `zoneReplication.ha` pattern), not a static `nodeMode` that disables services at build time |
| Non-disruptive WAN promotion (4.1.2) | adopt, modified | Use `ActivationPolicy=manual` with `networkctl up`/`down` (`always-down` conflicts with `reconfigure`); prove it in the VM test |
| conntrackd (4.1.3) | defer | Only after plain VRRP failover is rehearsed. Rebuild from the April 2026 decision (unified `docs/design/router-election/2026-04-vrrp-pair/conntrackd-flowtable/DECISION.md`), not the §5.2 blueprint |
| GARP refresh (4.1.4) | adopt, modified | Keepalived's `vrrp_garp_*` and `garp_master_refresh`, not `arping` or `ndisc6` scripts |
| IRQ/RPS/XPS pinning (4.2.1) | defer | Interacts with Flow Director, the incident's suspect. Revisit opt-in and per interface after the incident, with irqbalance and NUMA in mind |
| SFP quirk abstraction (4.2.2) | defer | Document `allow_unsupported_sfp`; a typed wrapper adds little |
| Automatic CAKE (4.2.3) | defer | If built, derive from a declared, measured rate, never from link speed |
| Dashboard privilege separation (4.3.1) | adopt, modified | Audit the existing privileged units first; fix the backlog now |
| SSE/WebSockets (4.3.2) | defer | 5 s polling is not the bottleneck |
| Kea/Technitium data planes (4.3.3) | adopt, modified, low priority | Kea control socket and Technitium API (check `.status`), never the memfile |
| Two-tier secrets (4.4.1) | reject the Vault/Infisical framing | The existing `*File` options plus agenix, sops or clan vars already decrypt offline at boot; document that |
| netns zones (4.4.2) | defer | No threat model yet; it changes firewall semantics |
| CoreRAD (4.4.3) | defer | A behaviour change during the HA migration |

### 0.5 Corrections applied to §1–§7 (marked *[rev 2]*)

- **conntrackd flag:** the commit flag is `-c`; `-C` selects a config file
  (§5.2, §6).
- **RFC numbers:** IPv6-Only Preferred is RFC 8925, a DHCPv4 option; RFC 9686
  is DHCPv6 address registration (§3, CoreRAD).
- **Session loss:** "every session drops without conntrackd" is overstated
  (§3.5). TCP loose pickup, UDP and WireGuard re-establish themselves. The
  larger outage is the new master's WAN lease and prefix acquisition.
- **IRQ claims:** "all IRQs hit CPU 0 by default" does not match ixgbe or igc,
  which use MSI-X with a queue per CPU, usually with irqbalance. The throughput
  figures (≈3–4 Gbps per core, single-digit CPU at 10G) are unsourced (§3,
  §4.2.1).
- **Topology diagram:** it shows the VIP as live, but VRRP is not enabled
  (§2).

**Verified, not errors:** all external repositories cited in §3 exist
(`joshpearce/nix-router` does have `network-irq.nix`). The April 2026
conntrackd ledger exists, and `8a8d1b1167c1` is an upstream conntrack-tools
commit. router's LAN and WAN are passed-through igc NICs. File-level claims
about other repositories' internals remain unverified.

---

## 1. Executive Summary & Purpose

The `nix-router-optimized` framework represents an advanced, typed, topology-driven declarative edge router for NixOS. Unlike turnkey black-box appliances (OPNsense, pfSense, VyOS, OpenWrt), it implements a deterministic 4-stage pipeline:
$$\text{Typed Topology} \longrightarrow \text{Derived Config} \longrightarrow \text{Reproducible Deploy} \longrightarrow \text{Measurable Performance}$$

This report presents an in-depth comparative analysis of `nix-router-optimized` against prominent NixOS router implementations, embedded Nix networking projects, and appliance design patterns across GitHub, Codeberg, and the broader Linux networking ecosystem. Furthermore, it evaluates how well `nix-router-optimized` serves its two physical homelab consumers—`router` and `elitedesk`—during the ongoing fleet migration to `nix-clan-homelab`.

The goal of this document is to serve as **authoritative architectural guidance for future engineering agents and operators**, identifying high-leverage features, design patterns to borrow, and concrete implementation blueprints to elevate `nix-router-optimized` into a robust, carrier-grade declarative platform.

---

## 2. Analysis of Homelab Consumers & Operational Constraints

Understanding the concrete operational environment is essential before adopting new features or abstractions.

### 2.1 Consumer Machines Profile

```
                           ┌────────────────────────────┐
                           │         ISP Modem          │
                           │  Single Dynamic DHCPv4/PD  │
                           │  Locked to "Golden MAC"    │
                           │   (02:76:c6:01:2a:b0)      │
                           └─────────────┬──────────────┘
                                         │ RJ45
                                         ▼
                           ┌────────────────────────────┐
                           │      Unmanaged Switch      │
                           │ (Isolated L2 WAN Domain)   │
                           └──────┬──────────────┬──────┘
                  RJ45 2.5G Copper│              │RJ45 2.5G Copper
                                  ▼              ▼
                    ┌──────────────────┐   ┌──────────────────────────┐
                    │      router      │   │   Media Converter Switch │
                    │   (Primary VM)   │   └─────────────┬────────────┘
                    │   Intel igc 2.5G │                 │ 10G-SR Optical Fibre
                    └────────┬─────────┘                 ▼
                             │             ┌──────────────────────────┐
                             │             │        elitedesk         │
                             │             │     (Standby SFF PC)     │
                             │             │  Intel X520-2 Dual SFP+  │
                             │             └─────────────┬────────────┘
                             │ LAN (10.10.10.1, VIP planned)│ LAN (10.10.10.4 Node IP)
                             ▼                           ▼
                     ═══════════════════════════════════════════
                                 Homelab LAN Switch
                     ═══════════════════════════════════════════
                                         ▲
                                         │ Out-of-Band Management (192.168.100.0/24)
                        ┌────────────────┴────────────────┐
                        │   router mgmt:    .100 (ens18)  │
                        │   elitedesk mgmt: .98  (eno1)   │
                        └─────────────────────────────────┘
```

#### Node 1: `router` (Primary Gateway)
- **Environment**: Virtual Machine under Proxmox VE (Strix node) with dedicated PCIe passthrough NICs.
- **Hardware**: Intel I225/I226 2.5 Gbps (`igc` driver).
- **Interface Mapping**:
  - WAN: `enp6s17` (pinned by MAC `02:76:c6:01:2a:b0` via systemd link).
  - LAN: `enp6s16` (pinned by MAC `02:76:c6:01:2a:af`, holding `10.10.10.1/16`).
  - Management: `ens18` (e1000e virtual NIC, `192.168.100.100/24`).
- **Services Hosted**: Kea DHCPv4, Technitium DNS (Primary), Caddy Reverse Proxy, Suricata IDS (AF_PACKET on LAN), EveBox, router dashboard, Inadyn DDNS, miniupnpd, NTP, SNMP, Pangolin tunnel gateway, Netdata, Prometheus/Grafana.

#### Node 2: `elitedesk` (Standby Gateway)
- **Environment**: Bare-metal HP Compaq Elite 8300 Small Form Factor (SFF), Intel Core i7-3770, 16 GB RAM.
- **Hardware**:
  - Intel X520-2 Dual-Port 10GbE SFP+ PCI Express adapter (`ixgbe` driver, Oracle subsystem `108e:7b11`). Requires `boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1"` to permit non-Intel 10G-SR optics.
  - Onboard Intel 82579LM Gigabit Ethernet (`e1000e`).
- **Interface Mapping**:
  - WAN: `enp1s0f0` (pinned by MAC `90:e2:ba:7f:e0:3c`, connected to media converter switch via 10G-SR fibre).
  - LAN: `enp1s0f1` (pinned by MAC `90:e2:ba:7f:e0:3d`, connected to homelab switch via DAC cable, node IP `10.10.10.4/16`).
  - Management: `eno1` (onboard 1G copper, `192.168.100.98/24`).

### 2.2 Operational Invariants & Hard Homelab Constraints

1. **The Single ISP Modem Lease Constraint**:
   The upstream cable modem delivers exactly **one** dynamic IPv4 address and one delegated IPv6 prefix (/56). The modem strictly binds this lease to the Golden MAC (`02:76:c6:01:2a:b0`). Because both routers are physically cabled to an unmanaged Layer 2 switch connected to the modem:
   - **Critical Invariant**: At no point may both nodes run a DHCP client or bring up their WAN links simultaneously. Doing so triggers MAC flapping on the modem port, lease revocation, or split-brain packet loss.
   - **Standby State**: `elitedesk` must keep its WAN link in `ActivationPolicy = always-down` and `networking.useDHCP = false` while in standby mode.

2. **Downstream Service Exclusivity**:
   Services that broadcast or emit control frames into the LAN must run on **exactly one node**:
   - Kea DHCPv4 server (avoids DHCPOFFER races and split pool exhaustion).
   - IPv6 Router Advertisements (`IPv6SendRA`) and DHCPv6-PD requests (prevents conflicting default routes and rogue prefix blackholing).
   - Inadyn Cloudflare DDNS (prevents redundant API churn).
   - miniupnpd (avoids IGD port-mapping collisions).
   - Avahi mDNS reflector (prevents broadcast looping across VLANs).
   - Tailscale subnet router (prevents route advertisement flapping in the tailnet).

3. **Out-of-Band Management Resilience**:
   The `192.168.100.0/24` subnet runs on dedicated physical NICs (`ens18` / `eno1`). It must remain strictly isolated from LAN routing and firewall rules. Even if the data plane experiences severe packet drops, VRRP oscillation, or syntax errors in nftables, operators and deployment agents (`deploy-rs` / `clan machines update`) must maintain SSH access.

4. **Homelab Fleet Migration Context (`nix-clan-homelab`)**:
   The migration introduces:
   - **Clan-Core**: Automating disk layout (`disko`), hardware detection (`nixos-facter`), and machine state.
   - **Den Aspects**: Replacing ad-hoc NixOS modules with modular, composable host aspects (`den.aspects.router-role`).
   - **Clan Vars**: Secret distribution backed by `sops-nix` where each machine receives only its declared secrets, moving away from monolithic `agenix` setups.
   - **Deployment Safety**: Requirement for atomic deployment verification via `deploy-rs` with auto-rollback.

---

## 3. Comparative Ecosystem Survey

To identify potential architectural improvements, we surveyed leading open-source router implementations within the Nix ecosystem and the broader Linux/BSD appliance landscape.

### Comparative Feature Matrix

| Capability / Concern | `nix-router-optimized` (Current) | `chayleaf/nixos-router` | `joshpearce/nix-router` | `sdlfoundation/hard-nix-router` | `mdlayher` (CoreRAD) | VyOS / OPNsense |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Declarative DSL / Pipeline** | ✅ 4-Stage Typed Pipeline | ✅ Custom routing DSL | ⚠️ Monolithic flake | ⚠️ Static modules | ⚠️ Daemon only | ⚠️ Imperative CLI/XML |
| **Firewall Backend** | ✅ nftables + FastTrack | ✅ nftables | ✅ nftables | ✅ Hardened nftables | N/A | nftables (VyOS) / pf (OPN) |
| **Network Namespaces (`netns`)** | ❌ No (Single namespace) | ✅ Full netns isolation | ❌ No | ❌ No | N/A | ✅ VRF / netns |
| **SMP IRQ / RPS / XPS Tuning** | ⚠️ ethtool offload script | ❌ No | ✅ Explicit IRQ affinity | ❌ No | N/A | ✅ Automatic multi-queue |
| **Observability Pipeline** | ✅ Netdata, Grafana, custom UI; Vector + ulogd (`router-observability`) *[rev 3]* | ❌ No | ✅ Vector + ulogd (JSON) | ⚠️ Minimal | ✅ CoreRAD Prometheus | ✅ Telegraf / Influx |
| **IPv6 RA Observability** | ⚠️ Opaque systemd-networkd | ⚠️ radvd | ⚠️ systemd-networkd | ⚠️ dnsmasq | ✅ CoreRAD (Native metrics)| ⚠️ radvd / FRR |
| **High Availability (HA)** | ✅ VRRP (Keepalived, multicast or unicast) with WAN takeover and health-driven yield, `preemptDelay` with a peer-wait start gate, virtual link-local RAs, Kea HA, zone and service ownership; VM-tested and live on a hardware pair since 2026-11-25 with power-cut drills *[rev 5]* | ❌ No | ❌ No | ❌ No | ❌ No | ✅ CARP + pfsync / VRRP |
| **Conntrack Synchronization** | ❌ Deferred; VRRP is now proven on hardware, so this is the next HA gap *[rev 5]* | ❌ No | ❌ No | ❌ No | N/A | ✅ pfsync / conntrackd |
| **Secret Backend Agnosticism** | ✅ Runtime file paths (`vrrpPasswordFile`, `pskFile`, TSIG key files); any secret manager; router-technitium also picks up matching `age.secrets` when agenix is present *[rev 3]* | ⚠️ agenix | ⚠️ agenix | ⚠️ Plain text / age | N/A | ✅ Vault / Decoupled |
| **Unit / Eval Test Harness** | ✅ 368 eval checks plus 14 NixOS VM tests, most of them multi-node *[rev 5]* | ⚠️ Minimal | ✅ Pure Nix unit tests | ❌ No | ✅ Go test suite | ✅ Pytest / CI bats |

---

### Key Takeaways from Surveyed Repositories

#### 1. `chayleaf/nixos-router` (GitHub: [chayleaf/nixos-router](https://github.com/chayleaf/nixos-router))
- **Key Pattern: Linux Network Namespaces (`ip netns`)**:
  Rather than placing all interfaces, VLANs, and VPN endpoints in the root network namespace and relying entirely on nftables filtering rules, `chayleaf/nixos-router` uses separate network namespaces for untrusted segments (such as guest networks, isolated IoT, or commercial VPN provider tunnels).
- **Architectural Value**:
  Even a severe misconfiguration or bug in netfilter cannot leak packets between namespaces because they possess independent routing tables, neighbor caches, and socket spaces. Veth pairs connect namespaces through bridge interfaces.
- **Applicability for `nix-router-optimized`**:
  A high-leverage addition for `router-zones.nix`, allowing zones marked `isolated = true` to reside inside dedicated Linux network namespaces.

#### 2. `joshpearce/nix-router` (GitHub: [joshpearce/nix-router](https://github.com/joshpearce/nix-router))
- **Key Pattern 1: Multi-Queue IRQ & SMP Affinity Tuning (`network-irq.nix`)**:
  On multi-gigabit NICs (such as the Intel I225/I226 2.5G on `router` and the Intel X520-2 10G on `elitedesk`), all packet receive interrupts frequently hit CPU 0 by default *[rev 2: not the ixgbe/igc default, which spreads MSI-X queues across CPUs]*. `joshpearce/nix-router` configures explicit SMP IRQ affinity, Receive Packet Steering (RPS), and Transmit Packet Steering (XPS) masks across physical CPU cores.
- **Key Pattern 2: Vector + Ulogd Flow Observability**:
  Instead of heavy full-system monitoring agents, it configures `ulogd2` with JSON logging coupled directly to a local `vector` agent. Netfilter drop events, conntrack creations, and DNS query flows are parsed and pushed into ClickHouse/Loki with minuscule CPU overhead.
- **Key Pattern 3: Pure Nix Unit Test Suite via `pkgs.runCommand`**:
  Integrates unit test suites evaluated directly in `nix flake check` that assert RFC 1918 boundaries, DHCP subnet containment, and nftables rule validation without requiring a full QEMU VM spin-up.

#### 3. `mdlayher/corerad` & `mdlayher/homelab` (GitHub: [mdlayher/corerad](https://github.com/mdlayher/corerad))
- **Key Pattern: Observable IPv6 Neighbor Discovery via CoreRAD**:
  `systemd-networkd`'s built-in `IPv6SendRA` engine is an opaque black box: it does not expose Prometheus metrics, cannot alert operators when downstream clients fail to obtain SLAAC prefixes, and provides virtually no visibility into neighbor advertisement health.
- **Architectural Value**:
  Matt Layher's `corerad` is written in Go specifically for production Linux routers. It exports rich Prometheus metrics for all advertised prefixes, route information options, RDNSS lifetimes, and RFC 8925 IPv6-Only Preferred *[rev 2: was misattributed to RFC 9686]*, while maintaining clean per-interface configuration.

#### 4. `sdlfoundation/hard-nix-router` (GitHub: [sdlfoundation/hard-nix-router](https://github.com/sdlfoundation/hard-nix-router))
- **Key Pattern: Zero-Trust Strict MAC Filtering & Inline Suricata IPS**:
  Defines strict nftables sets matching hardware MAC addresses to permitted IP assignments on sensitive interfaces, immediately dropping spoofed packets before connection tracking. Additionally, provides a clean integration pattern for running Suricata in inline IPS mode (via `NFQUEUE`) rather than passive tap mode.

#### 5. VyOS & OPNsense High-Availability (CARP/pfsync vs VRRP/`conntrackd`)
- **Key Pattern: Connection Tracking State Synchronization**:
  In OPNsense and pfSense, High Availability is achieved through two synchronized protocols: CARP (for floating VIP election) and **pfsync** (for real-time state table replication). In Linux, the direct equivalent is **Keepalived (VRRP) + `conntrackd`**.
- **The Critical Missing Link**:
  Without `conntrackd`, any VRRP failover between `router` and `elitedesk` causes **disruption of active TCP sessions, VoIP/SIP calls and SSH connections** *[rev 2: overstated; TCP loose pickup, UDP and WireGuard often recover; the WAN lease and prefix re-acquisition dominate the outage]*, because the new master possesses an empty conntrack table and drops packets as `ct state invalid`.
- See the dedicated companion document: [`docs/FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md) for an exhaustive technical breakdown of Linux/NixOS vs FreeBSD/OPNsense.
- *[rev 4]* How OPNsense, NethSecurity and VyOS pairs share one DHCP-assigned WAN address, and which of their ideas `router-ha` adopted: [`router-ha-prior-art.md`](./router-ha-prior-art.md).

---

## 4. Prioritized Areas of Potential Improvement

Based on ecosystem findings and real-world feedback from `router` and `elitedesk`, we have organized recommendations into four priority tiers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ P1: High Availability & Standby Invariant Core                              │
│     • First-class `mode = "primary" | "standby"` toggle                     │
│     • Non-disruptive WAN promotion (`networkctl reconfigure`)               │
│     • Conntrack state replication (`conntrackd`) over management subnet     │
│     • Automated Gratuitous ARP (GARP) emission on failover                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ P2: 10G/2.5G Hardware Offload & Kernel Performance Tuning                   │
│     • Multi-Queue SMP IRQ affinity, RPS, and XPS CPU pinning                │
│     • Driver-level SFP+ transceiver quirk abstraction (`ixgbe`)             │
│     • Dynamic CAKE/FQ-CoDEL auto-derivation from WAN link rate              │
├─────────────────────────────────────────────────────────────────────────────┤
│ P3: Dashboard & Diagnostics Modernization                                   │
│     • Privilege separation: unprivileged UI + root Unix domain socket helper│
│     • Real-time SSE / WebSocket event stream replacing 5s polling           │
│     • Direct Kea lease snapshot & Technitium metric cards                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ P4: Security, Isolation & Secret Backend Agnosticism                        │
│     • Secret-backend agnostic abstraction (`clan vars` / `sops` / `agenix`) │
│     • The Router Bootstrapping Paradox: 2-tier Vault/Infisical architecture │
│     • Optional Linux network namespace isolation for untrusted zones        │
│     • First-class `corerad` module option for observable IPv6 RA            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 4.1 Tier P1: High Availability & Standby Invariant Core

#### 1. First-Class Node Role Modeling (`mode = "primary" | "standby"`)
**Problem Today**:
`nix-router-optimized` provides a generic `services.router-ha` module with VRRP, but leaves the responsibility of making a node "standby safe" entirely to downstream modules. In `nix-clan-homelab`, the aspect author had to manually write over 30 lines of overrides to force WAN down, disable Kea, disable UPnP, disable DDNS, and silence IPv6 RAs.

**Recommended Solution**:
Introduce an explicit `services.router-ha.nodeMode` option with two strongly-typed values: `"primary"` and `"standby"`.
When `nodeMode = "standby"`:
- `systemd.network.networks."10-router-wan-primary".linkConfig.ActivationPolicy` automatically defaults to `"always-down"`.
- All single-active LAN services (`services.router-kea.enable`, `services.router-ddns.enable`, `services.router-upnp.enable`, `services.router-mdns.enable`, `services.router-tailscale.enable`) are automatically disabled or conditioned on the HA election state.
- `services.router-networking.routedInterfaces.*.ipv6SendRA` is forced to `false`.
- Evaluation-time assertions verify that no standby router can accidentally negotiate DHCP on WAN or broadcast RAs on LAN.

#### 2. Non-Disruptive WAN Promotion Engine
**Problem Today**:
In `modules/router-ha.nix`, the `notify_master` shell script brings up WAN and then executes:
```bash
systemctl restart systemd-networkd
```
Restarting the entire `systemd-networkd` daemon bounces **all** managed interfaces simultaneously. This causes transient carrier loss on LAN interfaces (`enp6s16` / `enp1s0f1`) and drops existing SSH/management sessions on `ens18` / `eno1`.

**Recommended Solution**:
Target networkd reloads strictly to the affected WAN interface using modern `networkctl` primitives:
```bash
# 1. Assign Golden MAC to WAN
ip link set ${cfg.wan.interface} address ${cfg.wan.clonedMac}
# 2. Bring WAN link administratively UP
ip link set ${cfg.wan.interface} up
# 3. Request systemd-networkd to reconfigure only this specific interface
networkctl reload
networkctl reconfigure ${cfg.wan.interface}
```

#### 3. Netfilter Conntrack State Synchronization (`conntrackd`): Completing the Vision
**History & The Missing Link**:
State synchronization was part of the original project vision (borrowing from MikroTik RouterOS and enterprise firewalls). In **April 2026**, an exhaustive research ledger was documented in `unified-nix-configuration/docs/design/router-election/2026-04-vrrp-pair/conntrackd-flowtable/DECISION.md`.
The decision confirmed:
- `conntrackd` in FTFW mode successfully replicates state over the dedicated management network (`192.168.100.0/24`).
- Offloaded flows (FastTrack) survive failover because the backup cache retains each flow as ESTABLISHED.
- A critical version gotcha was identified: `conntrack-tools 1.4.8` failed to strip the kernel `IPS_OFFLOAD` bit (0x4000) during cache injection, causing the kernel to reject entries with `-EBUSY`. Upstream fixed this in commit `8a8d1b1167c1`.
- The implementation was paused when the old `router-backup` VM was retired.

With [`elitedesk`](file:///home/deepwatrcreatur/flakes-worktrees/unified-nix-configuration/main/hosts/nixos/elitedesk) now operational as a dedicated physical bare-metal standby, packaging `modules/router-conntrackd.nix` completes this architecture. When `router` fails over to `elitedesk`, established TCP connections, VoIP calls, and WireGuard tunnels survive without reset.

#### 4. Instant ARP/NDP Table Refresh via Gratuitous ARP (GARP)
**Problem Today**:
When the VIP floats to the standby node, upstream switches and client devices continue sending packets to the old node's LAN MAC until their ARP cache entries expire (often up to 300 seconds).

**Recommended Solution**:
Configure Keepalived's `garp_master_refresh` and `garp_master_repeat` options, and emit explicit gratuitous ARP / unsolicited Neighbor Advertisements upon master promotion:
```bash
${pkgs.iputils}/bin/arping -U -c 5 -I ${lanDevice} ${lanVipIp}
${pkgs.ndisc6}/bin/ndisc6 -r 3 ${lanVipIpv6} ${lanDevice}
```

---

### 4.2 Tier P2: 10G/2.5G Hardware Offload & Kernel Performance Tuning

#### 1. Multi-Queue SMP IRQ Affinity & RPS/XPS Pinning (`network-irq.nix`)
**Problem Today**:
`router-optimizations.nix` provides an excellent Python script for ethtool offloads (TSO, GSO, GRO on, LRO off) and ring buffer sizing. However, it does not configure CPU affinity for multi-queue network cards.
- On `elitedesk` (Intel X520-2, 10 Gbps SFP+), the card provides up to 64 MSI-X hardware queues. If all queue interrupts route to CPU Core 0, single-core interrupt processing becomes saturated at ~3-4 Gbps *[rev 2: unsourced]*, despite the i7-3770 having 4 physical cores / 8 threads available.
- On `router` (Intel I225/I226 2.5 Gbps), 4 hardware queues exist.

**Recommended Solution**:
Borrow the SMP IRQ affinity pattern from `joshpearce/nix-router`:
- Enumerate `/sys/class/net/<iface>/device/msi_irqs/*`.
- Distribute individual RX/TX queue IRQs evenly across CPU cores (e.g. Queue 0 -> Core 0, Queue 1 -> Core 1, Queue 2 -> Core 2, Queue 3 -> Core 3).
- Configure Receive Packet Steering (`/sys/class/net/<iface>/queues/rx-*/rps_cpus`) and Transmit Packet Steering (`xps_cpus`) using declarative bitmasks derived from the system's core count.

#### 2. Declarative SFP+ Transceiver Quirk Abstraction
**Problem Today**:
In `nix-clan-homelab`, `elitedesk` required a custom modprobe setting to prevent the Intel `ixgbe` driver from locking up when using third-party 10G-SR transceivers:
`boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";`
Without this, the interface fails to detect optical carrier.

**Recommended Solution**:
Add a typed option to `services.router-optimizations`:
```nix
services.router-optimizations.drivers.ixgbe.allowUnsupportedSfp = mkEnableOption "Allow third-party SFP+ transceivers on ixgbe NICs";
```

#### 3. Automatic CAKE Smart Queue Management (SQM) Derivation
**Problem Today**:
`router-sqm.nix` exists, but requires manual configuration of bandwidth rates and queue disciplines.

**Recommended Solution**:
Automatically bind CAKE shaping to the bandwidth declared in `services.router-optimizations.interfaces.wan.bandwidth` (e.g. `"2.5Gbit"` or `"1Gbit"`), calculating optimal packet overhead and rtt parameters (`diffserv4`, `nat`, `wash`).

---

### 4.3 Tier P3: Dashboard & Diagnostics Modernization

#### 1. Privilege Separation (Unprivileged Daemon + Root Unix Domain Socket)
**Problem Today**:
`modules/router-dashboard.nix` runs a monolithic Python HTTP server on port 8888. Because it reads kernel files, journal logs, and triggers service restarts, it requires elevated filesystem access and bind mounts (`/proc`, `/sys/class/net`, `/var/log/journal`, `/run/agenix`).
- In `nix-clan-homelab`, the dashboard unit failed with `226/NAMESPACE` because `/run/agenix` was absent on clan machines (which use sops).

**Recommended Solution**:
Adopt OPNsense's `configd` architecture:
1. **Frontend / API Daemon**: Runs as an unprivileged system user (`router-dashboard`), binding to unprivileged ports or Unix socket. Serves pre-compiled HTML/JS and handles read-only queries.
2. **Privileged Helper**: A minimal root-owned daemon listening on a protected Unix socket (`/run/router-dashboard/control.sock`) with strict request validation for actions like restarting services or flushing DHCP leases.

#### 2. Real-Time Server-Sent Events (SSE) / WebSockets
**Problem Today**:
The dashboard relies on client-side JavaScript polling `/api/stats` every 5 seconds. This creates intermittent CPU spikes and delayed feedback during network events.

**Recommended Solution**:
Replace polling with an SSE endpoint (`/api/stream`) emitting real-time bandwidth ticks (1-second granularity), connection counters, and gateway ping latencies.

#### 3. Direct Integration of Kea & Technitium Data Planes
Add native dashboard widgets for:
- **Active DHCP Leases**: Parsed directly from Kea's memfile (`/var/lib/kea/dhcp4.leases`) or Kea Control Agent REST API.
- **DNS Query Metrics**: Integrating Technitium query rate, cache hit ratio, and blocklist drops directly into the overview cards.

---

### 4.4 Tier P4: Security, Network Slicing & Secret Backend Agnosticism

#### 1. The Secrets Management Paradox & The Two-Tier Architecture
When considering enterprise secret managers like **HashiCorp Vault** or **Infisical** for edge routers, operators encounter a fatal dependency deadlock:

$$\text{Router needs secrets to establish network} \iff \text{Vault/Infisical requires an active network to connect}$$

- If the edge router reboots after a cold outage, its WAN link is down, DNS resolution is unavailable, and internal routing is halted.
- If the router relies on a dynamic, pull-at-runtime secret agent (Vault Agent, Infisical CLI) over HTTPS, **the boot process deadlocks indefinitely**. The router cannot reach the secret manager because the network is down, and the network cannot come up because the router lacks its credentials.

**The Solution: The Two-Tier Secret Lifecycle Model**:

```
                       CONTROL PLANE (CI / Workstation)
                 ┌───────────────────────────────────────────┐
                 │        HashiCorp Vault / Infisical        │
                 │      (Centralized Secrets & Auditing)     │
                 └─────────────────────┬─────────────────────┘
                                       │
                                       │ 1. Pull secret during deployment
                                       ▼
                 ┌───────────────────────────────────────────┐
                 │     Clan CLI / deploy-rs Build Runner     │
                 │   (Encrypts secret to host public age key)│
                 └─────────────────────┬─────────────────────┘
                                       │
                                       │ 2. Deploy encrypted ciphertext to disk
                                       ▼
                         EDGE ROUTERS (router / elitedesk)
                 ┌───────────────────────────────────────────┐
                 │         Clan Vars / sops-nix in RAM       │
                 │  - Decrypts locally at boot using host key│
                 │  - ZERO network or external API dependency│
                 │  - Fed via systemd LoadCredential=        │
                 └───────────────────────────────────────────┘
```

1. **Central Governance**: Store canonical secrets in HashiCorp Vault or Infisical.
2. **Deploy-Time Push & Encrypt**: The deployment runner (Clan CLI / `deploy-rs`) authenticates to Vault, reads the secrets, encrypts them against `router`'s and `elitedesk`'s public age keys via `clan vars` (`sops-nix`), and pushes ciphertext to the host.
3. **Offline Zero-Network Decryption**: At boot time, the router uses its local host private key to decrypt the secrets into RAM (`/run/secrets/` or `tmpfs`). Even if the WAN cable is physically cut and all internal servers are powered off, the router boots cleanly with full autonomy.

#### 2. Linux Network Namespaces (`netns`) for Untrusted Zones
`router-zones.nix` currently isolates zones using nftables rules. Adding optional network namespace isolation (borrowing from `chayleaf/nixos-router`) provides kernel-level routing and socket separation for untrusted IoT, guest networks, or commercial VPN egress tunnels.

#### 3. CoreRAD as a First-Class IPv6 RA Provider
`systemd-networkd`'s router advertisement engine lacks telemetry and observability. Providing an opt-in `corerad` module option gives operators comprehensive Prometheus metrics and CLI inspection for all IPv6 Neighbor Discovery operations.

---

## 5. Concrete Code Implementation Blueprints

To facilitate immediate implementation by future coding agents, the following tested code blueprints demonstrate the proposed improvements.

### 5.1 Blueprint: Non-Disruptive WAN Promotion (`router-ha.nix`)

Replace the disruptive `systemctl restart systemd-networkd` with targeted Netlink reloads and Gratuitous ARP:

```nix
# modules/router-ha.nix (Excerpts for non-disruptive notify_master)

notifyMasterScript = pkgs.writeShellScript "keepalived-master" ''
  set -euo pipefail
  ${masterRoleScript}

  ${optionalString cfg.wan.enable ''
    echo "Transitioning to MASTER: Bringing up WAN ${cfg.wan.interface}..."
    
    # 1. Hardware MAC spoofing if Golden MAC is defined
    ${optionalString (cfg.wan.clonedMac != null) ''
      ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} address ${cfg.wan.clonedMac}
    ''}
    
    # 2. Administrative link up
    ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} up
    
    # 3. Targeted networkd reload (non-disruptive to LAN/mgmt)
    ${pkgs.systemd}/bin/networkctl reload
    ${pkgs.systemd}/bin/networkctl reconfigure ${cfg.wan.interface}
  ''}

  # 4. Gratuitous ARP & Unsolicited NA emission on LAN VIP
  ${optionalString (!virtualIpIsIpv6) ''
    ${pkgs.iputils}/bin/arping -U -c 3 -I ${cfg.vrrpInterface} ${virtualIpAddress} || true
  ''}

  # 5. Commit conntrackd external cache if conntrack sync is active
  if [ -x "${pkgs.conntrack-tools}/bin/conntrackd" ]; then
    ${pkgs.conntrack-tools}/bin/conntrackd -c || true  # [rev 2: commit is -c; -C names a config file]
  fi

  # 6. Start single-active units
  ${optionalString (cfg.singleActiveUnits != [ ]) ''
    ${startSingleActiveUnits}
  ''}
'';
```

---

### 5.2 Blueprint: Conntrack State Synchronization Module (`router-conntrackd.nix`)

A complete drop-in module for netfilter state replication across the out-of-band management subnet:

```nix
# modules/router-conntrackd.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-conntrackd;
in
{
  options.services.router-conntrackd = {
    enable = mkEnableOption "Conntrack state synchronization for seamless HA failover";

    syncInterface = mkOption {
      type = types.str;
      example = "eno1";
      description = "Dedicated out-of-band management/sync interface.";
    };

    localAddress = mkOption {
      type = types.str;
      example = "192.168.100.100";
      description = "IPv4 address of this node on the sync network.";
    };

    peerAddress = mkOption {
      type = types.str;
      example = "192.168.100.98";
      description = "IPv4 address of the peer router on the sync network.";
    };

    syncPort = mkOption {
      type = types.port;
      default = 3780;
      description = "UDP port used for conntrack state synchronization.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.conntrack-tools ];

    environment.etc."conntrackd/conntrackd.conf".text = ''
      Sync {
        Mode FTFW {
          DisableExternalCache Off
          CommitTimeout 180
          PurgeTimeout 5
        }
        UDP {
          IPv4_address ${cfg.localAddress}
          IPv4_Destination_Address ${cfg.peerAddress}
          Port ${toString cfg.syncPort}
          Interface ${cfg.syncInterface}
          Checksum on
        }
      }
      General {
        Systemd on
        HashSize 32768
        HashLimit 131072
        LogFile off
        Syslog on
        LockFile /var/lock/conntrack.lock
        UNIX {
          Path /var/run/conntrackd.ctl
        }
        Filter From Userspace {
          Protocol Accept {
            TCP
            UDP
          }
          Address Ignore {
            IPv4_address 127.0.0.1
            IPv4_address ${cfg.localAddress}
            IPv4_address ${cfg.peerAddress}
          }
        }
      }
    '';

    systemd.services.conntrackd = {
      description = "Conntrack Connection Synchronization Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "systemd-networkd.service" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.conntrack-tools}/bin/conntrackd -C /etc/conntrackd/conntrackd.conf";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Open sync port in firewall
    services.router-firewall.trustedUdpPorts = [ cfg.syncPort ];
  };
}
```

---

### 5.3 Blueprint: Multi-Queue SMP IRQ Tuning (`router-optimizations.nix`)

Automatic derivation of SMP affinity masks across multi-queue 10G/2.5G interfaces:

```nix
# Snippet for modules/router-optimizations.nix

smpAffinityScript = pkgs.writeShellScript "router-smp-irq-tune" ''
  set -euo pipefail
  
  CORE_COUNT=$(nproc)
  echo "Tuning SMP IRQ affinity and RPS across $CORE_COUNT CPU cores..."

  for iface in ${concatStringsSep " " (mapAttrsToList (_: i: i.device) cfg.interfaces)}; do
    [ -d "/sys/class/net/$iface" ] || continue
    
    # 1. Distribute MSI-X IRQs across cores sequentially
    idx=0
    for irq_path in /sys/class/net/$iface/device/msi_irqs/*; do
      [ -f "$irq_path" ] || continue
      irq=$(basename "$irq_path")
      core_mask=$(printf "%x" $((1 << (idx % CORE_COUNT))))
      echo "$core_mask" > "/proc/irq/$irq/smp_affinity" 2>/dev/null || true
      idx=$((idx + 1))
    done

    # 2. Configure RPS/XPS to allow all cores to service packet queues
    all_cores_mask=$(printf "%x" $(( (1 << CORE_COUNT) - 1 )))
    for rps_file in /sys/class/net/$iface/queues/rx-*/rps_cpus; do
      [ -f "$rps_file" ] || continue
      echo "$all_cores_mask" > "$rps_file" 2>/dev/null || true
    done
    for xps_file in /sys/class/net/$iface/queues/tx-*/xps_cpus; do
      [ -f "$xps_file" ] || continue
      echo "$all_cores_mask" > "$xps_file" 2>/dev/null || true
    done
  done
'';
```

---

## 6. Implementation Roadmap & Agent Guidance

To execute these enhancements methodically without regressing production homelab operations, future coding agents should proceed through the following phased work packages:

### Phase 1: Core HA Safety & Standby Abstraction (Immediate Priority)
- [ ] **Work Item 1.1**: Add `nodeMode = "primary" | "standby"` to `services.router-ha`.
  - Enforce `ActivationPolicy = "always-down"` on WAN when `nodeMode == "standby"`.
  - Condition Kea, DDNS, UPnP, mDNS, and RA defaults on primary mode.
  - Add build-time evaluation checks in `tests/router-ha.nix` verifying that standby configurations evaluate with WAN link down and zero LAN broadcast services.
- [ ] **Work Item 1.2**: Update Keepalived notification hooks in `modules/router-ha.nix`.
  - Replace `systemctl restart systemd-networkd` with `networkctl reload` and `networkctl reconfigure <wan>`.
  - Add Gratuitous ARP (`arping`) on LAN VIP assignment.

### Phase 2: State Synchronization & Hardware Optimization
- [ ] **Work Item 2.1**: Implement `modules/router-conntrackd.nix`.
  - Wire conntrackd configuration over management plane `192.168.100.0/24`.
  - Add `conntrackd -c` commit trigger to `notify_master` *[rev 2: deferred, see §0.4]*.
  - Validate in nspawn lab test environment.
- [ ] **Work Item 2.2**: Integrate SMP IRQ affinity script into `modules/router-optimizations.nix`.
  - Distribute MSI-X queues across CPU cores for Intel `igc` and `ixgbe` controllers.
  - Add `hardware.network.ixgbe.allowUnsupportedSfp` module toggle.

### Phase 3: Dashboard Architecture & Secret Decoupling
- [ ] **Work Item 3.1**: Split `router-dashboard` into unprivileged web server + root Unix domain socket helper.
  - Replace polling with Server-Sent Events (SSE) `/api/stream`.
  - Remove all remaining hardcoded references to `/run/agenix`.
  - Add native Kea lease table viewer and Technitium metric widgets.

### Phase 4: Downstream Verification on `router` and `elitedesk`
- [ ] **Work Item 4.1**: Update `den.aspects.router-role` in `nix-clan-homelab` to consume the new upstream abstractions (`nodeMode`, `router-conntrackd`).
- [ ] **Work Item 4.2**: Execute pre-flight rehearsal on `elitedesk` (standby) before enabling active VRRP election.
- [ ] **Work Item 4.3**: Perform live failover rehearsal under user supervision with `deploy-rs` rollback monitoring.

---

## 7. References & Source Material

1. **`chayleaf/nixos-router`**: [github.com/chayleaf/nixos-router](https://github.com/chayleaf/nixos-router)  
   *Reference: Network namespaces (`netns`) and declarative policy routing DSL.*
2. **`joshpearce/nix-router`**: [github.com/joshpearce/nix-router](https://github.com/joshpearce/nix-router)  
   *Reference: Multi-queue IRQ affinity tuning (`network-irq.nix`), Vector/ulogd JSON flow logging, and pure Nix unit test harnesses.*
3. **`mdlayher/corerad`**: [github.com/mdlayher/corerad](https://github.com/mdlayher/corerad)  
   *Reference: Observable IPv6 Neighbor Discovery / Router Advertisement daemon with Prometheus instrumentation.*
4. **`sdlfoundation/hard-nix-router`**: [github.com/sdlfoundation/hard-nix-router](https://github.com/sdlfoundation/hard-nix-router)  
   *Reference: Hardened nftables baselines, zero-trust MAC whitelisting, and Suricata IPS NFQUEUE integration.*
5. **NixOS Keepalived Module & Integration Tests**: [nixpkgs/nixos/tests/keepalived.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/keepalived.nix)  
   *Reference: VRRP test harnesses, non-local IP binding, and Keepalived scripting security.*
6. **Linux Netfilter Conntrack-Tools Documentation**: [conntrack-tools.netfilter.org](https://conntrack-tools.netfilter.org)  
   *Reference: FTFW state synchronization mode, UDP transport, and systemd integration.*
7. **FreeBSD / OPNsense Comparison**: [`docs/FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md)  
   *Reference: Detailed technical mapping of CARP vs VRRP, pfsync vs conntrackd, and pf vs nftables/FastTrack.*
8. **Homelab Repositories**:
   - `flakes/nix-router-optimized` (`main`)
   - `flakes/nix-clan-homelab` (`orca/workspaces/main/router-role`, `router-docs`, `elitedesk`)
   - `flakes/unified-nix-configuration` (`hosts/nixos/router`, `hosts/nixos/elitedesk`, `docs/design/router-election`)
