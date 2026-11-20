## Discussion 22: Review of the VyOS feature parity plan

**Status:** closed (round 1). The findings are applied in revision 2 of
[`../VYOS-FEATURE-PARITY-PLAN.md`](../VYOS-FEATURE-PARITY-PLAN.md).
**Date:** 2026-11-20
**IC:** Claude
**Subject:** `docs/VYOS-FEATURE-PARITY-PLAN.md` (commit 44992a6), written by
another chatbot.
**Roster:** Codex (`codex exec`, read-only sandbox), Gemini (`agy -p` with a
"no tools" instruction; it signed its position "Antigravity"), Claude
(`claude -p`), Copilot (`copilot -p`), DeepSeek (API, `deepseek-chat`; it
signed its position "Claude" by mistake). Full quorum.

**Context given to every voice:** the verified state on 2026-11-20 (HA PRs
#153 to #158 merged, the Technitium NOTIFY fix pending as #159, no live
failover on hardware yet) and the IC fact-check below, so the voices argued
judgement rather than facts.

### IC fact-check

Checked before the round (given to every voice):

- **`routerctl` already exists** (`pkgs/router-diag`, a flake package) with
  `status`, `interfaces`, `health`, `diagnostics`, `firewall
  summary/explain/trace` and `--json`. The plan's Phase 1 proposes a new
  `router-cli` without mentioning it.
- **router-ha does not use conntrackd.** Discussion 21 deferred it until
  plain VRRP failover is rehearsed on hardware.
- **The repo has 56 modules**, not "38+". `router-pppoe`, `router-mwan` and
  `router-zones` exist. There is no DHCPv6 server module.
- **Wrong paths in the plan:** the Kea socket is `/run/kea/dhcp4.sock`; the
  HA role is in `/run/router-ha/role`; the WAN option is
  `services.router-networking.wan.device`.
- **nixpkgs:** FRR and strongswan-swanctl have NixOS modules; igmpproxy
  (0.4) and smcroute (2.5.7) are packaged without modules.
- **VyOS 1.4 documents flowtable offload** (software and hardware) and has
  a CAKE QoS policy, so neither is an advantage over VyOS.

Checked after the round, where voices disagreed:

- **keepalived and BFD.** Upstream keepalived supports BFD tracking, but
  the nixpkgs build is configured without `--enable-bfd` (its config options
  list no BFD and the binary has no `track_bfd`). Codex's `track_bfd`
  suggestion needs a package override; Gemini's "keepalived lacks native
  BFD" is true only of this build.
- **DHCP relay in systemd-networkd.** `[DHCPServer]` has `RelayTarget=`,
  `RelayAgentCircuitId=` and `RelayAgentRemoteId=` in systemd 259 (Claude
  was right).
- **VyOS and Kea.** VyOS moved its DHCP server to Kea in the 1.5 line
  (January 2024); 1.4 still uses ISC dhcpd. Claude's "VyOS 1.4 moved to
  Kea" is wrong. `commit-confirm`, `compare` and `rollback-soft` (rollback
  without reboot) are in 1.4.
- **Gemini's errors:** VTI adds no GRE overhead, and a NixOS rollback does
  not need a reboot (`nixos-rebuild switch --rollback`); reverting does need
  a working path to the machine, which is the real gap.

### Codex

**Q1 Accuracy and framing.** The comparison reads as advocacy. Pin VyOS 1.4 and a specific rolling build separately, and distinguish upstream capability, flake integration, VM evidence, and hardware evidence.

- Nix evaluation validates declared configuration. DHCP leases, daemon state, and live forwarding can still diverge. A bootable generation provides a recovery point, while restoring connectivity takes time and may require console access. VyOS also has per-image configuration, confirmed commits, and revision comparison. Cite specific migration failures or drop the generalization. [VyOS upgrades](https://docs.vyos.io/en/1.4/installation/update.html) · [VyOS CLI](https://docs.vyos.io/en/1.4/cli.html)
- Shared FRR establishes a common engine. Compare exposed address families, policy, and operational workflows before claiming BGP parity. Describe Technitium and overlays as integrated features. Publish throughput only with a reproducible workload, NIC, packet sizes, and enabled policies. Replace day estimates with scoped milestones covering lifecycle, firewall policy, and interoperability tests.
- BFD detection uses the negotiated interval and the transmitting peer’s multiplier. Symmetric 300 ms × 3 gives nominal detection around 900 ms, before route or VRRP convergence. Separate OSPFv2/v3 from IS-IS and distinguish protocol support from a deployment requirement. [RFC 5880](https://www.rfc-editor.org/rfc/rfc5880)
- Cloud requirements vary by gateway. AWS virtual private gateways support static and dynamic routing, Azure has policy-based and route-based options, and Google HA VPN uses BGP while Classic supports static routing. VTI and XFRM are Linux implementation choices. [AWS](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNRoutingTypes.html) · [Azure](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq) · [Google Cloud](https://docs.cloud.google.com/network-connectivity/docs/vpn/concepts/overview) · [strongSwan](https://docs.strongswan.org/docs/latest/features/routeBasedVpn.html)
- The IPTV freeze timing and cause are unverified. Qualify support per provider, access network, and receiver. Verify VLAN and provisioning requirements, IGMP version and source-specific membership, and stream delivery with multiple receivers. `quickleave` can disrupt remaining viewers. [igmpproxy](https://github.com/pali/igmpproxy)

[satisfied]

**Q2 Fit to goals and priorities.** Prioritize EliteDesk cutover safety and HA hardening. Extend `routerctl` alongside that work because it directly helps operators rehearse and diagnose failover. First verify X520 and switch behavior in a controlled rehearsal with console recovery. Resolve WAN health tracking, delegated-prefix continuity, and the pending DNS ownership fix before relying on HA for primary service. Add three-candidate testing and check whether WAN, LAN, and service ownership need VRRP sync groups to move together.

For wider adoption, prioritize timed rollback, a candidate-versus-active config diff, and documented zone firewall policies with an explainable effective ruleset. Put DHCP relay and DHCPv6 server/PD for downstream routers ahead of speculative protocol work. Treat downstream PD serving separately from preserving the ISP-delegated prefix across failover. Revisit conntrack sync after hardware rehearsal measures established-session loss. After that, prioritize IPsec, OSPF, then BFD where a peer and convergence goal exist. Let a documented IPTV or AV topology drive multicast scheduling. [VyOS CLI](https://docs.vyos.io/en/1.4/cli.html) · [Keepalived configuration](https://www.keepalived.org/documentation/keepalived-conf/)

[satisfied]

**Q3 Item verdicts.**

- **`routerctl` — adopt-modified.** Extend HA and DHCPv4 inspection with stable JSON and explicit unavailable states. **Reject** a duplicate CLI. Check packaging at eval time and exercise healthy, degraded, and disabled services in the HA VM.
- **`router-ipsec` — adopt-modified.** Reuse `strongswan-swanctl`, start with XFRM interfaces and runtime credentials, and add VTI only for a demonstrated local compatibility need. Compose optional BGP through `router-bgp`. Require explicit tunnel zones and scope IKE/ESP allowances to configured WAN and peers. Eval IDs and firewall scope. Test rekey, BGP withdrawal/recovery, and blocked cleartext fallback against an IKE/FRR peer VM. [strongSwan](https://docs.strongswan.org/docs/latest/features/routeBasedVpn.html)
- **`router-ospf` — adopt-modified.** Start with OSPFv2 and share FRR configuration ownership with BGP. Stage OSPFv3 separately and make redistribution opt-in. Eval coexistence and passive interfaces. Test adjacency, route withdrawal, and recovery with an FRR peer VM.
- **`router-bfd` — defer.** Start with FRR routing consumers once a convergence target exists. Evaluate Keepalived’s native `track_bfd` separately with an independent reachable peer and an explicit priority policy. Eval timers and bindings. Blackhole traffic with carrier up and measure detection, route withdrawal, and any VRRP transition separately. [Keepalived configuration](https://www.keepalived.org/documentation/keepalived-conf/)
- **`router-multicast` — adopt-modified.** Qualify `igmpproxy` for a supported membership-driven IPTV topology and `smcroute` for explicit multicast routes. Scope automatic rules to configured interfaces, sources, and groups, with IGMP on the relevant links. Eval scopes. Use sender and receiver VMs to test join/leave, two viewers, and isolation from other VLANs. [igmpproxy](https://github.com/pali/igmpproxy) · [SMCRoute](https://github.com/troglobit/smcroute)
- **EVPN/VXLAN — defer.** A VXLAN netdev is only one component. Eval VNI/bridge mappings and test MAC learning, isolation, and withdrawal across two FRR VTEP VMs.
- **DHCP relay/Option 82 — adopt-modified.** Start with IPv4 relay and explicit Option 82 trust policy. Eval interface/server mappings. Test lease allocation, renewal, and forged Option 82 handling with client, relay, and Kea VMs.
- **NetFlow/IPFIX — defer.** Require a collector use case and define offload visibility. Eval exporter options. Test decoded records and accounting with a collector VM and flowtable enabled and disabled.

[satisfied]

**Q4 Next steps.** Track six items now.

1. **EliteDesk rehearsal.** Record X520 link/VLAN behavior and client outage during planned and abrupt handoffs. Demonstrate console recovery and restoration of the incumbent router.
2. **WAN health and three-candidate election.** A carrier-up upstream outage demotes the master to a healthy candidate. Recovery respects configured hysteresis, with one owner after convergence.
3. **IPv6 PD continuity.** Under a simulated ISP that binds leases to client identity, preserve the delegated prefix across handoff and verify client IPv6 reachability and router advertisements.
4. **Technitium ownership.** Land the pending fix with a VM check for post-handoff updates, NOTIFY, and secondary convergence.
5. **`routerctl` HA visibility.** Stable JSON exposes role, WAN health, and Kea HA state, with VM coverage for unavailable data and no credential output.
6. **Timed rollback and preview.** Show effective network and firewall changes, then demonstrate that an unconfirmed management lockout automatically restores access in a VM.

Rename the document **VyOS comparison and router roadmap**. Update the 56-module inventory and verified paths, replace superiority labels and fixed estimates, and label each capability by evidence level and deployment relevance.

[satisfied]

### Gemini (agy)

**Q1 Accuracy and framing.** Beyond the verified IC fact-check, the plan suffers from critical architectural misconceptions, flawed protocol assertions, and biased framing:
1. *VyOS Characterization & "NixOS Superiority"*: Claiming NixOS has "zero runtime drift" while dismissing VyOS as "mutable at runtime" mischaracterizes both architectures. VyOS is a purpose-built appliance OS with a transactional CLI, commit-confirm safety, config diffing, and live rollbacks without dropping traffic. Conversely, the plan claims NixOS offers "sub-second bootloader rollbacks"—ignoring that bootloader rollback requires a cold reboot (costing minutes of downtime on bare metal like the elitedesk X520). Furthermore, claiming FastTrack flowtables and CAKE as NixOS-exclusive differentiators is false: VyOS 1.4+ natively supports nftables flowtables (hardware/software) and CAKE queuing.
2. *Protocol & Hardware Claims*:
   - *BFD Timings*: The plan claims BFD sends "microsecond heartbeats" via FRR. Linux userspace `bfdd` operates in the tens-to-hundreds of milliseconds (typically 50–300 ms). Sub-millisecond or microsecond BFD requires dedicated hardware ASIC offload or kernel bypass (DPDK/XDP).
   - *Keepalived/BFD Coupling*: Keepalived lacks native BFD integration; tying them together requires fragile shell tracking scripts, introducing latency that defeats sub-second failover.
   - *Cloud IPsec (VTI vs. XFRM)*: Major cloud providers (AWS, Azure, GCP) do not mandate VTI. VTI (`ip_vti`) is legacy, IPv4-only, and carries GRE overhead. Modern Linux and cloud interconnects use XFRM interfaces (`xfrmi`), which natively handle dual-stack IPv4/IPv6 over a single SA with clean routing table isolation.
   - *IPTV & Multicast*: Blaming IPTV stream freezes solely on upstream IGMP forwarding is simplistic. FTTH providers (e.g., Orange, Deutsche Telekom) require 802.1p egress VLAN priority tagging (CoS), vendor-specific DHCP option 60, and IGMPv3 SSM. Conflating `igmpproxy` (dynamic proxy) with `smcroute` (static kernel routing daemon) demonstrates an architectural gap.
3. *Effort Estimates*: The 2–4 day timelines are severely underestimated for production NixOS modules requiring option schemas, assertions, systemd integration, and multi-node VM test suites.
4. *Community Framing*: The document reads as partisan advocacy rather than an objective engineering roadmap. Dismissing VyOS’s operational maturity while glossing over NixOS’s lack of safe live commit-confirm harms community trust. — [satisfied-conditional: Strip ungrounded superiority claims, correct protocol errors (BFD, VTI/XFRM, IPTV), and recalibrate effort estimates to account for VM test harnesses]

**Q2 Fit to goals and priorities.** The four proposed gaps do **not** serve the maintainer’s goals better than finishing HA hardening. For an elitedesk bare-metal primary router, unhardened HA invites household network blackouts during uplink drops or maintenance. 

The plan missed vital operational capabilities central to both goals:
1. *Safe Deployment / Commit-Confirm*: Guarding against remote lockout (`nixos-rebuild switch` bricking connectivity without automatic watchdog rollback).
2. *VRRP Sync Groups & Uplink Health Tracking*: Tracking WAN carrier and gateway reachability to depress VRRP priority on upstream failure, preventing blackholing.
3. *IPv6 Prefix Delegation (DHCPv6-PD) Persistence*: Stable DUID/IAID handling across failover so LAN clients retain valid IPv6 routes.
4. *Zone-Based Firewall Ergonomics*: VyOS excels at high-level zone policies; raw nftables across 56 modules quickly becomes unmaintainable.

*Proposed Priority Ordering*:
1. **HA & Hardware Hardening** (WAN track script, VRRP sync groups, DHCPv6-PD stability, physical elitedesk validation).
2. **Operational Safety & Tooling** (Commit-confirm / rollback watchdog, expanding `routerctl`).
3. **Core Edge Networking** (DHCPv6 server module, DHCP relay).
4. **Dynamic Routing & Interconnect** (OSPFv2/v3 via FRR, strongSwan IPsec via XFRM).
5. **Niche Features** (igmpproxy for IPTV, BFD, NetFlow). — [satisfied-conditional: Reprioritize immediate roadmap around HA completion, deployment safety, and IPv6 parity before introducing enterprise routing protocols]

**Q3 Item verdicts.**
- **`routerctl` extension vs. new `router-cli`**: **adopt-modified** (extend `routerctl`). Avoid fragmentation by enhancing the existing `router-diag` package with Kea `/run/kea/dhcp4.sock` parsing and `/run/router-ha/role` state reporting. *Testing*: NixOS VM test asserting `routerctl --json` output against mock daemon sockets.
- **`router-ipsec`**: **adopt-modified**. Reject VTI; implement strongSwan `swanctl` with XFRM interfaces (`systemd-networkd` `[XFRM]` netdevs) and automated ESP/IKE firewall opening. Defer BGP-over-IPsec. *Testing*: 2-node NixOS VM test asserting established IKEv2/ESP SAs and bi-directional ping across XFRM.
- **`router-ospf`**: **adopt**. Natural extension of existing `services.frr` (`router-bgp`) for homelab L3 core switch integration. *Testing*: 2-node NixOS VM test verifying OSPFv2/OSPFv3 adjacency and kernel FIB route insertion.
- **`router-bfd`**: **adopt-modified**. Adopt FRR `bfdd` for native OSPF/BGP link health; reject Keepalived integration as brittle. *Testing*: Multi-node VM test simulating link down and verifying sub-second OSPF route withdrawal.
- **`router-multicast`**: **adopt-modified**. Implement `igmpproxy` with automated nftables rules for IGMP (protocol 2) and multicast UDP; reject `smcroute`. *Testing*: Multi-node VM test with `iperf`/`socat` validating UDP multicast stream transit from upstream to downstream receiver.
- **`EVPN/VXLAN`**: **defer**. Datacenter fabric overlay with negligible ROI for edge/homelab routers. *Testing*: Eval assertions verifying `systemd-networkd` netdev generation only.
- **`DHCP relay / Option 82`**: **adopt-modified**. Package a lightweight relay agent (`dhcrelay` or Kea relay) for campus/homelab setups with centralized DHCP. *Testing*: VM test with client, relay router, and upstream Kea instance validating Option 82 injection.
- **`NetFlow / IPFIX`**: **reject**. Redundant with existing Vector + ulogd NFLOG (`router-observability`) and `router-ntopng`. *Testing*: Flake eval checks verifying observability module builds. — [satisfied-conditional: Enforce strict test gating (VM tests with simulated peers for adopted networking modules, eval-only for deferred) and replace VTI with XFRM]

**Q4 Next steps.** Rename `docs/VYOS-FEATURE-PARITY-PLAN.md` to `docs/ROUTER-CAPABILITIES-ROADMAP.md`, replacing adversarial parity claims with an objective gap analysis. Track the following 5 work items:
1. **WAN Tracking & VRRP Sync in `router-ha`**: Implement a Keepalived track script monitoring gateway reachability to reduce master priority on WAN failure. *Acceptance*: Two-router VM test where dropping simulated WAN triggers failover within 3 seconds.
2. **DHCPv6-PD Lifecycle & DUID Persistence**: Implement stable DUID configuration and prefix distribution across HA nodes. *Acceptance*: VM test verifying backup router inherits the identical delegated prefix upon takeover without client lease renewal failures.
3. **Extend `routerctl` with Socket Inspection**: Add `routerctl ha` and `routerctl leases` reading `/run/router-ha/role` and `/run/kea/dhcp4.sock`. *Acceptance*: `routerctl --json` outputs structured status validated in VM test suite.
4. **`router-ospf` Module via FRR**: Expose declarative OSPFv2/OSPFv3 configuration options mapped to `services.frr.ospfd`. *Acceptance*: Multi-node NixOS VM test establishing full adjacency and injecting connected routes.
5. **Safe Deployment & Auto-Rollback Guard**: Build a `routerctl apply --confirm <sec>` utility that automatically rolls back generation if not confirmed by operator. *Acceptance*: Automated test confirming rollback execution when confirmation token is not supplied. — [satisfied-conditional: Track these 5 discrete work items with VM test criteria and rename/refactor the parity document]

### Claude

**Q1 Accuracy and framing.** Beyond the IC fact-check:
- **VyOS is described as it was years ago.** VyOS 1.4 moved its DHCP server to Kea. It serves DHCPv6 and prefix delegation, has zone-based firewall, conntrack-sync, WAN load balancing, an HTTP API, `commit-confirm`, `compare` and `rollback`, and can archive commits remotely. Its images are squashfs, so "mutable Debian base" is wrong. Its flowtable support is documented, not "experimental".
- **"Parity+" on HA is false.** There is no conntrackd and no "Golden MAC cloning" claim backed by code. There has been no failover on real hardware yet.
- **The "NixOS Superior" verdicts are overstated.** Rolling back to an older generation needs a reboot or a remote `switch`. It is not "sub-second", and a bad network change can cut off the operator before they can roll back. "Zero runtime drift" ignores runtime state: leases, Technitium zones created through the API, and keepalived state. NixOS's real advantage is eval-time typing and reproducible closures. Its real gap is that nothing reverts a bad change automatically, which VyOS's `commit-confirm` does.
- **Protocol errors:**
  - BFD sends packets at millisecond intervals, not "microsecond". Detection time is multiplier × interval, so the plan's own 300 ms × 3 gives about 900 ms, not "<300 ms".
  - Cloud IPsec: AWS and Classic GCP also support static routing, and Azure supports policy-based tunnels. Only some products (GCP HA VPN, AWS Transit Gateway with ECMP) actually require BGP. "Mandate route-based" is wrong. The MTU of 1436 is unverified.
  - IPTV: the "freezes after 5–10 s" symptom isn't backed by anything. Frozen streams are more often caused by a missing IGMP querier or a timed-out membership. Many ISPs deliver IPTV on a separate VLAN or PPPoE session, not on "the WAN interface". The `10.0.0.0/8` altnet example is arbitrary. Sonos and similar devices mostly need SSDP or mDNS relaying, not multicast routing.
- **Effort estimates of 2–5 days are not credible** for this repo's standard (module, docs, eval check, VM test with a simulated peer). HA alone took five PRs in a week and still hasn't been tested on real hardware.
- **Framing:** a community audience will check the VyOS claims and stop trusting the document. The honest selling points are typed Nix modules, a reproducible system, and no licence fee (VyOS LTS images are paid). Present CAKE, flowtables and Technitium as choices this flake makes, not as things VyOS lacks. — [satisfied]

**Q2 Fit to goals and priorities.** The four "gaps" serve neither goal as well as finishing HA. Elitedesk becoming primary depends on HA hardening and safe change management, not OSPF or IPsec. Proposed order:
1. **Finish HA.** Lower VRRP priority when the master's WAN fails (track script). Make the LAN and WAN VRRP instances fail over together (sync group). Keep the delegated prefix stable across failover (same DUID). Rehearse failover on elitedesk with the X520.
2. **Commit-confirm-style auto-rollback** for remote `switch`, plus a config diff (closure diff and rendered nftables/keepalived/Kea diff). Both make the move to elitedesk safer and appeal strongly to the community.
3. **Extend `routerctl`** with HA, lease and DNS views.
4. **DHCPv6/PD serving downstream.** Check what networkd's RA and DHCPv6 support already covers first.
5. **DHCP relay** (cheap, see Q3).
6. Then multicast/IPTV and IPsec, if community demand justifies them. OSPF, BFD and EVPN come last.

conntrack-sync stays deferred until plain VRRP has been rehearsed on hardware. Firewall zones already exist (router-zones), so improving their UX is a docs and `routerctl explain` task, not a new module. — [satisfied]

**Q3 Item verdicts.**
- **routerctl vs new router-cli: adopt-modified.** Extend `routerctl` with `ha` (reads `/run/router-ha/role`), `leases` (`/run/kea/dhcp4.sock`, v4 only), `dns`, `routes` (`vtysh` JSON) and `flows`, all with `--json`. Don't build a second CLI. Test: assert the JSON shape of each subcommand inside the existing two-router HA VM test.
- **router-ipsec: defer, then adopt-modified.**
  - Use the nixpkgs `strongswan-swanctl` module with XFRM interfaces (`if_id`, IPv6-clean, networkd `Kind=xfrm`), not VTI.
  - BGP over the tunnel goes through router-bgp. Firewall automation goes through router-zones.
  - Must document that SAs re-establish after a VRRP failover (no SA sync) and that flowtable offload may interact with XFRM; verify the latter.
  - Test: VM test against a strongSwan peer, checking SA established, BGP Established over the XFRM interface, and ping through it.
- **router-ospf: defer.** It's a thin layer over `services.frr`, but neither goal needs it. Test: two FRR VMs reaching an OSPF Full adjacency and installing the route (`show ip ospf neighbor json`).
- **router-bfd: defer.** On a shared LAN segment, VRRPv3 adverts at centisecond intervals already give sub-second failover. If BFD is ever added, prefer keepalived's own BFD tracking (`vrrp_track_bfd`; check whether the nixpkgs build enables it) over FRR bfdd driving track scripts. The WAN next-hop problem belongs to the HA track-script work. Test: VM test where dropping the peer link causes a BACKUP→MASTER transition within the configured detection time.
- **router-multicast: adopt-modified, after HA.**
  - Backend: igmpproxy for IPTV (one upstream, dynamic joins); smcroute only for static cross-VLAN routes.
  - Upstream must be a configurable interface, possibly a VLAN, never assumed to be the WAN.
  - nftables rules: allow IGMP on the upstream, forward 224.0.0.0/4 only to listed downstreams; also handle `rp_filter`.
  - Docs must make no ISP-specific promises.
  - Test: VM test with a simulated upstream sending to a group (`smcroute`/`iperf -u`). Downstream joins and receives, and stops receiving after a leave.
- **EVPN/VXLAN: reject** for this flake's edge-router scope.
- **DHCP relay/option 82: adopt (small).** systemd-networkd's `[DHCPServer]` has `RelayTarget=`, `RelayAgentCircuitId=` and `RelayAgentRemoteId=`. Wrap these as an option; this needs no new daemon. Test: eval check, plus a VM test with a relay VM and a Kea server VM where the client gets a lease through the relay.
- **NetFlow/IPFIX: defer.** If added, make it an option of router-observability (ulogd2 IPFIX output or pmacct). Must account for offloaded flows that bypass the normal netfilter path. Test: VM test with a collector receiving records. — [satisfied]

**Q4 Next steps.** Track these now:
1. **VRRP WAN track script.** Acceptance: in the two-router VM test, cutting the master's WAN moves the VIP to the backup in ≤5 s and LAN clients keep internet access.
2. **Stable delegated prefix across failover.** Acceptance: after failover in the VM test (simulated ISP with PD), the same delegated /56 appears on both nodes.
3. **Failover rehearsal on hardware** (maintainer-run, documented runbook). Acceptance: planned and crash failover between elitedesk (X520) and the current router, with timings recorded in `docs/`.
4. **Auto-rollback switch.** Acceptance: a VM test applies a configuration that breaks management access, does not confirm, and the router returns to the previous generation within the timeout.
5. **routerctl `ha`/`leases`/`dns` subcommands.** Acceptance: stable `--json` schema, asserted in the HA VM test.
6. **DHCP relay option.** Acceptance: the relay VM test above passes.

**Fixing the plan document:**
- Rename it to `VYOS-COMPARISON.md`, marked "Exploratory comparison — not a roadmap".
- Correct every IC finding and the Q1 items: Kea in VyOS, commit-confirm, flowtables, CAKE, conntrackd, paths, module count (~56, not "38+").
- Replace the verdict columns with "VyOS has / we have / gap / priority".
- Delete the effort estimates.
- Replace the CLI section with a pointer to `routerctl`.
- Link the roadmap to the issues above instead of the four phases. — [satisfied-conditional: the maintainer agrees that HA hardening and auto-rollback come before any new protocol module]

### GitHub Copilot

**Q1 Accuracy and framing.** The plan's VyOS characterization is stale and self-serving: VyOS 1.4 already ships flowtable offload (software and hardware) and CAKE, yet the plan claims these as NixOS "advantages" while its own table lists CAKE under VyOS too — an internal contradiction. "NixOS Superior" verdicts for config model and lifecycle are reasonable, but "Parity+" for HA is wrong on a factual claim (router-ha does not use conntrackd; that was explicitly deferred). BFD "<300ms" and IGMP "freeze after 5–10 seconds" are plausible-sounding but unsourced numbers presented as established fact — they should be marked as typical/vendor-reported, not measured. Effort estimates ("2–3 days" for a CLI, "3–5 days" for IPsec+VTI+BGP) are not credible given this repo's own practice of pairing every behavior change with a VM test; testing alone likely doubles each estimate. Cloud IPsec claims (AWS/Azure/GCP needing route-based VTI) are directionally correct but presented as "non-negotiable" when static/policy-based IPsec is also commonly accepted by those providers. Framing is not dishonest in intent but is unbalanced: it undersells VyOS's maturity in exactly the areas (multicast, IPsec, BFD) it then proposes to copy, which weakens credibility with a knowledgeable community audience.

**Q2 Fit to goals and priorities.** No — all four gaps are tangential to "elitedesk becomes a safely-failing-over primary router with VRRP candidates." None touch VRRP track scripts, DUID/prefix stability, or hardware failover rehearsal, which are the actual open risks today. Ordering: (1) finish HA hardening — track script lowering priority on WAN failure, stable delegated prefix across failover, then a real hardware failover drill; (2) only then take community-facing items. For the second goal (attractiveness to the NixOS-router community), the plan missed higher-value VyOS features than its four picks: commit-confirm/auto-rollback (huge trust feature, and NixOS's generation rollback is a natural fit to extend, not compete with), config diff/compare across generations, DHCP relay (more commonly needed in homelabs with existing DHCP infra than OSPF/EVPN), VRRP sync groups and interface health tracking (directly extends router-ha, this quarter's work), and zone-firewall UX (explain/trace already exist in routerctl — promote and document these rather than reinvent).

**Q3 Item verdicts.**
- routerctl extension vs new router-cli: **adopt-modified** — extend existing `routerctl` (status/interfaces/health/diagnostics/firewall already there); do not fork a new tool. Test: extend existing router-diag eval checks with new subcommands' `--json` output.
- router-ipsec (swanctl, VTI/XFRM, BGP-over-IPsec, firewall automation): **adopt-modified** — valuable but scope first pass to swanctl config + VTI + firewall rules only; defer BGP-over-IPsec to a follow-up once base tunnels are proven. Test: two-VM NixOS test standing up a tunnel between simulated sites, verifying VTI route and ESP/IKE firewall rules.
- router-ospf: **defer** — real need (L3 core switch) isn't present in the stated homelab goal; revisit if a user/maintainer gets a managed L3 switch. Test when built: 3-node VM test with redistribute connected/static.
- router-bfd (incl. tying into keepalived): **adopt-modified, but reorder after HA track scripts** — tying BFD into keepalived's existing VRRP health tracking is more valuable than BFD for BGP/OSPF given no OSPF exists yet. Test: VM test asserting BFD-triggered VRRP transition latency, not just FRR bfdd config.
- router-multicast (igmpproxy vs smcroute, IPTV, firewall automation): **adopt-modified** — real homelab pain point (ISP IPTV) genuinely matters; prefer igmpproxy for simplicity (smcroute lacks a NixOS module either way, so both need packaging work). Test: VM test with simulated IGMPv3 source and querier-side join verification.
- EVPN/VXLAN: **reject** for now — no stated multi-site L2 need; door open if homelab grows multi-site.
- DHCP relay/option 82: **adopt** — higher real-world value than three of the four "gaps," especially for anyone with existing enterprise DHCP. Test: VM test relaying a DISCOVER/OFFER across a non-Kea upstream server.
- NetFlow/IPFIX: **defer** — router-observability (Vector/ulogd/Prometheus) already covers this need; document rather than duplicate.

**Q4 Next steps.** Track now, in this order: (1) VRRP track script to lower priority on WAN failure — acceptance: VM test shows BACKUP promotes within existing ~4s window when MASTER's WAN link is cut, not just when keepalived itself dies; (2) stable delegated prefix/DUID across failover — acceptance: VM test confirms same IPv6 PD prefix survives a VRRP transition; (3) real hardware failover rehearsal on elitedesk + one VRRP candidate — acceptance: documented drill with measured failover time, written up in docs/; (4) routerctl subcommands for HA/leases/routes (absorbing Work Item 1) — acceptance: `routerctl` gains `ha`, `leases`, `routes` with `--json`, covered by existing router-diag checks; (5) router-multicast (igmpproxy) — acceptance: VM test with simulated IGMPv3 source passes; (6) DHCP relay module — acceptance: VM test relays across a non-Kea DHCP server. Document fixes: correct all wrong paths (Kea socket, HA role path, `wan.device`), remove/caveat the DHCPv6-leases CLI example (no DHCPv6 server exists), strike the CAKE/flowtable "advantage" framing or reframe as "parity, not advantage," and relabel the doc from "Parity Plan" to "Backlog Candidates — Unprioritized, Pending HA Hardening" until items 1–3 above land.

[satisfied-conditional: reorder so HA hardening (VRRP track scripts, stable DUID/prefix, hardware failover drill) lands before any Phase 1–4 item is started, and correct the factual errors (conntrackd, paths, DHCPv6, CAKE/flowtable "advantage" framing) before this becomes tracked work]

### DeepSeek

**Q1 Accuracy and framing.** Beyond the IC fact-check, the plan has several problems. (a) VyOS characterisation is a strawman: VyOS 1.4/1.5 has `commit-confirm` (auto-rollback on lost session), `compare`/`show configuration diff`, `rollback N`, image-based upgrades with boot-to-previous, and `show` operational commands — the plan's "imperative-under-the-hood, mutable, breaks on upgrade" framing is dated and will read as uninformed to VyOS users. (b) "NixOS Superior" verdicts on config model and lifecycle are defensible but overstated: NixOS has no `commit-confirm` equivalent out of the box (you can lose SSH mid-`nixos-rebuild switch` and be locked out), no config diff UX, and no `show` hierarchy — the plan's own Phase 1 admits this, contradicting the table. (c) FastTrack "vs standard conntrack" is wrong: VyOS 1.4 documents flowtable offload (software and hardware); the plan's own table lists it. (d) CAKE: VyOS has a CAKE QoS policy; "superior latency control" is not a differentiator. (e) BFD "<300ms" is a claim about configured intervals, not a guarantee; BFD detect time = multiplier × negotiated interval, and 300ms×3 = 900ms, not <300ms — the plan's own example contradicts its prose. (f) IPTV: "streams freeze after 5–10s" is provider-specific folklore; igmpproxy vs smcroute have different semantics (proxy vs static joins) and neither alone solves IGMPv3 SSM or source-specific joins common on DT/Orange. (g) Cloud IPsec: AWS/Azure/GCP all support policy-based IPsec and static routing; "mandate route-based + BGP" is false — route-based is preferred, not required. (h) Effort estimates (2–5 days each) are fantasy for modules with VM tests, firewall automation, and docs; the HA work this week took far longer per PR. (i) The plan never mentions `routerctl`, conntrackd deferral, the missing DHCPv6 server, or the wrong paths — it reads as if written against an imagined repo. Framing is not honest for a community audience: it invites rebuttal from VyOS maintainers and undersells the actual HA work.

**Q2 Fit to goals and priorities.** No. Goal (1) is "elitedesk safely primary, then VRRP candidates" — that is HA hardening, not IPsec/OSPF/multicast. Goal (2) is community attractiveness — the highest-leverage items are the ones the plan omits: commit-confirm-style auto-rollback (huge for remote routers), config diff/compare, DHCP relay + option 82, DHCPv6/PD serving (Kea DHCPv6), VRRP sync groups and interface/route health tracking (the open WAN-failure track script), conntrack-sync (deferred but the #1 question every HA user asks), and zone-firewall UX. Proposed ordering: (0) finish HA: WAN-failure track script lowering VRRP priority, stable delegated prefix across failover (DUID), live hardware failover rehearsal, conntrackd decision; (1) routerctl extension (not new CLI); (2) commit-confirm/auto-rollback + config diff; (3) DHCP relay/option 82 and DHCPv6/PD; (4) IPsec (strongSwan swanctl); (5) OSPF; (6) BFD; (7) multicast; defer EVPN/VXLAN and NetFlow.

**Q3 Item verdicts.**
- **routerctl extension vs new router-cli**: adopt-modified — extend `routerctl` (already has status/interfaces/health/diagnostics/firewall/--json); add `ha`, `leases` (DHCPv4 only), `routes`, `flows`, `dns`. Reject new `router-cli`. Test: eval checks on package contents + a NixOS VM test asserting `routerctl --json status` parses and reports role from `/run/router-ha/role`.
- **router-ipsec (strongSwan swanctl, VTI vs XFRM, BGP over IPsec, firewall automation)**: adopt-modified — use swanctl (nixpkgs has `services.strongswan-swanctl`), prefer XFRM interfaces over VTI (VTI is legacy, XFRM is the modern route-based choice), auto-open UDP 500/4500 + ESP, integrate with router-bgp. Test: two-NixOS-VM test with swanctl peer, assert tunnel up, BGP session Established over XFRM, and nft rules present.
- **router-ospf**: adopt-modified — drive FRR via nixpkgs `services.frr` (ospfd/ospf6d), not a bespoke config writer; reuse router-bgp patterns. Test: two-VM OSPF adjacency, route exchange, passive interface assertion via eval.
- **router-bfd (incl. keepalived tie-in)**: adopt-modified — FRR `bfdd` for BGP/OSPF; keepalived track script for VRRP is separate and should be the HA follow-up, not bundled. Fix the timing claim (detect = multiplier × interval). Test: VM test with `tc netem`/link drop, assert BFD down and BGP reconverge; keepalived track script tested in the existing VRRP lifecycle VM.
- **router-multicast (igmpproxy vs smcroute, IPTV, firewall)**: adopt-modified — ship igmpproxy as default (proxy semantics match IPTV), expose smcroute as alternative; document IGMPv3/SSM limits; auto-open IGMP + 224.0.0.0/4 to downstream VLANs only. Test: VM test with a simulated upstream multicast source and a downstream client joining; assert forwarding and nft rules.
- **EVPN/VXLAN**: defer — real but niche; systemd-networkd VXLAN + FRR EVPN is a large project with no homelab pull yet.
- **DHCP relay/option 82**: adopt — high community value, Kea can relay; test with two-VM relay + option 82 assertion.
- **NetFlow/IPFIX**: defer — router-observability/ntopng already cover the need; revisit if users ask.

**Q4 Next steps.** Track now: (1) HA WAN-failure track script lowering VRRP priority — acceptance: VM test where master's WAN drops, priority lowers, backup preempts within N seconds; (2) stable delegated prefix across failover (DUID) — acceptance: two-router VM test, prefix unchanged after failover; (3) live hardware failover rehearsal on elitedesk — acceptance: documented runbook + observed failover time; (4) extend `routerctl` with `ha`/`leases`/`routes`/`flows` — acceptance: `--json` schema + VM test; (5) commit-confirm/auto-rollback — acceptance: VM test where a switch that kills SSH auto-reverts; (6) DHCP relay + option 82 — acceptance: two-VM relay test. Correct the plan: relabel as "VyOS feature survey (draft, unverified)", remove the false FastTrack/CAKE/cloud-mandate claims, fix BFD timing, replace `router-cli` with `routerctl` extension, fix all paths (`/run/kea/dhcp4.sock`, `/run/router-ha/role`, `wan.device`), drop DHCPv6 leases from CLI scope, note conntrackd is deferred, and add a "HA hardening first" section before any parity work.

[needs more evidence: VyOS 1.4/1.5 commit-confirm, diff, and flowtable behaviour should be verified against upstream docs before the comparison is published; and the plan's effort estimates need a maintainer sanity check against this week's HA PR velocity.]

### Synthesis — Q22

**Q1 Accuracy and framing.** All five agree the plan reads as advocacy and
describes VyOS as it was years ago. Corrections accepted:

- **VyOS has what the plan says it lacks:** flowtable offload, CAKE,
  `commit-confirm`, `compare`, `rollback-soft`, conntrack-sync, zone
  firewall, WAN load balancing, image-based upgrades.
- **"Parity+" on HA is false:** no conntrackd, and no failover on real
  hardware yet.
- **"NixOS Superior" is overstated:** rollback is not sub-second and needs
  a path to the machine; "zero runtime drift" ignores leases, API-created
  zones and keepalived state. The honest advantage is eval-time typing and
  reproducible closures; the honest gap is that nothing reverts a bad change
  automatically.
- **Protocol errors:** BFD runs at millisecond, not microsecond, intervals,
  and detection is multiplier x interval (the plan's 300 ms x 3 is about
  900 ms, not "<300 ms"). Clouds do not mandate route-based IPsec (AWS and
  Classic GCP allow static routing, Azure offers policy-based). The IPTV
  "freezes after 5-10 s" claim is unsourced, IPTV often arrives on its own
  VLAN, and Sonos-style discovery needs SSDP/mDNS relaying, not multicast
  routing.
- **Effort estimates** of 2-5 days are not credible for a module with docs,
  eval checks and a VM test.

Marker: [satisfied-conditional: the document is corrected and relabelled as
a comparison, not a roadmap, before it is used as a work source.] Done in
revision 2.

**Q2 Priorities.** 5/5: the four "gaps" serve neither goal as well as
finishing HA. Order:

1. **Finish HA:** lower VRRP priority when the master's WAN fails
   (router-afb), keep the delegated prefix across failover (router-5sa),
   then the hardware failover rehearsal on elitedesk (nix-clan-homelab
   nch-sny.36).
2. **Safe change:** commit-confirm style auto-rollback with a config diff
   (router-113).
3. **Operator visibility:** extend `routerctl` (router-dke).
4. **Common edge needs:** DHCP relay (router-yix); a decision on DHCPv6/PD
   serving (router-xm6).
5. **Demand-driven:** multicast/IPTV (router-n3i), then IPsec (router-3op).
   OSPF and BFD are deferred (router-j93).

conntrack-sync stays deferred (discussion 21). Zone firewall UX is a docs
and `routerctl explain` task; `router-zones` exists. Marker: [satisfied].

**Q3 Item verdicts** (majority, with the deciding argument):

| Item | Verdict | Why |
| --- | --- | --- |
| New `router-cli` | reject (5/5) | Duplicates `routerctl`; extend it instead (router-dke) |
| router-ipsec | adopt-modified, after HA (4/5) | strongSwan swanctl with XFRM interfaces, not VTI (Copilot preferred VTI first); firewall scoped to configured peers; SAs re-establish after failover |
| router-ospf | defer (3/5) | Thin layer over `services.frr`, but no current peer or need |
| router-bfd | defer (3/5) | VRRP adverts already fail over in seconds on one segment; FRR consumers first; keepalived BFD needs an override |
| router-multicast | adopt-modified, after HA (5/5) | igmpproxy default, smcroute for static routes; upstream is a configurable interface; scoped nftables and rp_filter |
| EVPN/VXLAN | reject (3/5) / defer (2/5) | Out of scope for an edge-router flake |
| DHCP relay / option 82 | adopt (5/5) | Cheap through networkd `RelayTarget=`; higher demand than the four "gaps" |
| NetFlow/IPFIX | defer (4/5) | router-observability and ntopng cover it; must account for offloaded flows |

Marker: [satisfied].

**Q4 Tracked work** (beads created 2026-11-20):

| Bead | Item | Priority |
| --- | --- | --- |
| router-afb | VRRP priority follows WAN health (existing, raised to P1) | P1 |
| router-5sa | Keep the delegated prefix across failover | P1 |
| router-113 | Commit-confirm style auto-rollback and config diff | P2 |
| router-dke | `routerctl` ha, leases, dns, routes | P2 |
| router-yix | DHCP relay and option 82 via networkd | P3 |
| router-xm6 | Decide DHCPv6/PD serving for downstream networks | P3 |
| router-n3i | router-multicast (igmpproxy) | P3 |
| router-3op | router-ipsec (swanctl, XFRM) | P4 |
| router-j93 | OSPF and BFD (deferred) | P4 |
| router-ytw | Refresh the VyOS comparison and the ecosystem feature matrix once the above land | P3 |

The hardware rehearsal stays in nix-clan-homelab (nch-sny.36).
Marker: [satisfied].
