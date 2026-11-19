## Discussion 21: Review of the ecosystem research and improvement plan

**Status:** closed (round 1)
**Date:** 2026-11-19
**IC:** Claude
**Subject:** `docs/ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md` and
`docs/FREEBSD-OPNSENSE-COMPARISON.md` (commit bb22521), written by another
chatbot.
**Roster:** Codex (`codex exec`, read-only sandbox), Gemini (`agy -p`; the
first attempt tried a shell command, was denied and returned nothing, so it was
re-run with a "no tools" instruction), Claude (`claude -p`), Copilot
(`copilot -p`), DeepSeek (API, `deepseek-flash`; it signed its position
"Codex" by mistake). Full quorum.

**Context given to every voice:** the verified state as of 2026-11-19:
- shipped: `preemptDelay` (#144), Technitium zone replication and
  `zoneReplication.ha` (#145, #148, #149), router-alerting (#150), the
  dashboard link fix (#146);
- not done: no live failover yet, and DHCP is single-active;
- open: the X520 TCP reply-loss incident.

### IC fact-check

The voices disagreed on facts, so I checked them on 2026-11-19:

- **Every external repository the plan cites exists:**
  - `chayleaf/nixos-router` (416 stars)
  - `joshpearce/nix-router` (10 stars; `network-irq.nix` exists)
  - `sdlfoundation/hard-nix-router` (3 stars, last push 2025-01)
  - `mdlayher/corerad` and `mdlayher/homelab`

  Claude, Copilot and DeepSeek suspected fabrication; that suspicion was
  wrong. File-level claims about what those repos contain remain unverified.
- **The "April 2026 conntrackd ledger" is real:**
  unified-nix-configuration
  `docs/design/router-election/2026-04-vrrp-pair/conntrackd-flowtable/DECISION.md`.
  `8a8d1b1167c1` is an upstream conntrack-tools commit cited there, not a
  commit in our repos.
- **`modules/router-ha.nix:80` really restarts systemd-networkd** in
  `notify_master`.
- **The VRRP password defaults to `nix-router-ha`** and ends up in the Nix
  store (Claude's finding).
- **Discussion 20's work items WI-95 to WI-99 are closed** in this repo's
  beads: topology assertions, the hardware safety matrix, the multi-node VM
  test harness, `routerctl`, and slice isolation. Several voices treated
  these as still missing.


### Codex

**Q1 Accuracy and provenance.** — [needs more evidence: the April ledger, upstream fix, and blueprint test results need reproducible references]

- The baseline omits shipped `preemptDelay`, Technitium TSIG AXFR/NOTIFY and VRRP ownership reconciliation, alerting with a delivered test alert, and the dashboard link fix. DNS promotion was rehearsed manually. DHCP promotion is still manual and homelab VRRP is disabled. The Proxmox VM and Clan-managed bare-metal host remain in separate consumer repos. The dashboard already runs as `router-dashboard`, has separate privileged units, and tolerates a missing `/run/agenix`. [Dashboard unit](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/incident/modules/router-dashboard.nix:1013)
- All named project repositories exist. Chayleaf documents per-namespace routing and filtering, but the claimed immunity to packet leakage is unjustified wherever veths, bridges, or routes connect namespaces. Josh Pearce documents Vector/ulogd and tests, and its IRQ file uses host-specific IRQ numbers and RPS masks. The XPS attribution, precise test coverage, ClickHouse/Loki pipeline and “minuscule” overhead need file-level evidence. Hard Nix Router advertises MAC filtering and IDS. The precise pre-conntrack bindings and inline NFQUEUE IPS attribution remain unverified. [Chayleaf](https://github.com/chayleaf/nixos-router) · [Josh Pearce](https://github.com/joshpearce/nix-router) · [IRQ source](https://github.com/joshpearce/nix-router/blob/main/network-irq.nix) · [Hard Nix Router](https://github.com/sdlfoundation/hard-nix-router)
- CoreRAD provides RA metrics. RFC 9686 covers DHCPv6 address registration, so the “IPv6-Only Preferred” attribution is wrong. RFC 9568 supersedes RFC 5798 for VRRPv3. CARP and VRRP have analogous roles and distinct wire protocols. OPNsense provides XMLRPC configuration sync. The grouped “VRF / netns,” “Vault / Decoupled,” and “Pytest / CI bats” cells need product-specific evidence. [CoreRAD](https://github.com/mdlayher/corerad) · [RFC 9686](https://www.rfc-editor.org/rfc/rfc9686.html) · [RFC 9568](https://www.rfc-editor.org/rfc/rfc9568.html) · [OPNsense HA](https://docs.opnsense.org/manual/how-tos/carp.html)
- The WAN hook really restarts networkd. The claimed universal carrier and SSH loss needs measurement. `networkctl reload` can reconfigure other links, `always-down` conflicts with promotion by bare `ip link up`, and `ndisc6` solicits a neighbor. The conntrack cache commit flag is lowercase `-c`. Cache injection alone cannot guarantee TCP, SIP, or WireGuard continuity, and the claimed universal session loss without it is also too broad. Verify the 1.4.8 diagnosis and `8a8d1b1167c1` against the pinned build. [WAN hook](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/incident/modules/router-ha.nix:71) · [networkctl](https://www.freedesktop.org/software/systemd/man/latest/networkctl.html) · [NDisc6](https://www.remlab.net/ndisc6/) · [conntrack-tools](https://conntrack-tools.netfilter.org/manual.html)
- Treat queue counts, CPU0 saturation at 3–4 Gbps, single-digit CPU at 10G, and comparative nftables/XDP superiority as unsubstantiated for these hosts. “Carrier-grade,” “100% bit-identical,” and “zero drift” overstate the evidence. Thirty seconds is a configurable deploy-rs confirmation default. Management reachability can survive a forwarding failure and therefore cannot validate router health by itself. [deploy-rs](https://github.com/serokell/deploy-rs)

**Q2 Priorities.** — [satisfied]

Move incident qualification ahead of P1. The X520’s reported 1–8% TCP failure and prior PCIe disappearance make it a cutover blocker. ATR is a hypothesis. Separate wire-level loss from dashboard backlog saturation. Next prove a reversible single-router switchover, then exercise two-node VRRP before adding candidates. Split P1 so exclusive WAN and service ownership precede session preservation. For community adoption, bring forward Discussion 20’s tests, diagnostics, compatibility evidence and minimal example. Put performance tuning and new UI features behind measured need.

**Q3 Item verdicts.** — [satisfied]

- **Node role modeling — adopt-modified.** Model candidate eligibility, priority and runtime ownership independently, preserving existing option behavior and supporting three or more candidates.
- **`networkctl reconfigure` WAN promotion — adopt-modified.** Prove WAN-only transitions and DHCPv4/PD readiness on the pinned systemd, including demotion and failed promotion.
- **conntrackd — defer.** Measure recovery first. Later test NAT, offloaded flows, peer resync and version skew on an isolated sync path.
- **GARP refresh — adopt-modified.** Measure Keepalived’s built-in GARP and unsolicited NA convergence before tuning repetitions on Proxmox and the physical switch.
- **IRQ/RPS/XPS pinning — defer.** Measure RSS and IRQ distribution first. Guest vCPU affinity and bare-metal queue placement have different constraints.
- **SFP quirk abstraction — defer.** Keep the driver-wide opt-in in host configuration until a reusable need emerges.
- **Automatic CAKE — reject.** Ethernet link speed cannot determine ISP bottleneck rates, framing overhead, or policy.
- **Dashboard privilege separation — adopt-modified.** Audit existing privileged units and narrow the action surface. Measure backlog and concurrency before adding a root broker.
- **SSE/WebSockets — defer.** Establish capacity for long-lived clients and reconnect bursts first.
- **Kea/Technitium data planes — adopt-modified.** Consume bounded read-only snapshots or metrics with freshness indicators and restricted lease visibility.
- **Two-tier secrets — adopt-modified.** Accept runtime credential files and test offline boot. Leave centralized vault selection to consumers.
- **Netns zones — defer.** Define an isolation use case and test routing, DHCP/RA, observability and HA across boundaries.
- **CoreRAD — defer.** Require a concrete telemetry need and verify dynamic PD and exclusive RA ownership first.

**Q4 Gaps and next steps.** — [satisfied-conditional: live cutover requires hardware qualification and a successful rollback rehearsal]

Keep Discussion 20 as the maturation roadmap. Fold the new proposals into WI-95–99 where they fit, preserving topology assertions, firewall explainability and resource isolation. Track five items now. [Discussion 20](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/incident/docs/discussions/20-critique-synthesis-and-framework-roadmap.md:2023)

1. **X520 qualification.** Capture both ends, correlate TCP and UDP probes with NIC and PCIe counters, compare a known-good NIC, and set a soak and acceptance threshold before cutover.
2. **VM CI.** Add a WAN simulator and test startup, partition, hook failure, reboot, delayed failback, and third-candidate recovery. Assert exclusive WAN MAC, DHCP and RA ownership. Require fencing or fail-closed behavior when ownership is ambiguous.
3. **Cutover runbook.** Rehearse manual promotion with console access, abort criteria and tested failback. Measure forwarding, DNS, DHCP and IPv6 recovery before enabling VRRP.
4. **Upgrade safety.** Test pinned and mixed generations, rolling upgrades, and recovery of persistent DHCP/DNS state alongside system rollback.
5. **Diagnostics and provenance.** Add `routerctl` ownership and readiness output. Publish a minimal consumer example and a compatibility matrix with pinned sources and explicit eval, VM, hardware and live evidence.

### Gemini (agy)

**Q1 Accuracy and provenance.** The documents blend valid Linux networking primitives with significant inaccuracies, stale codebase assumptions, and ungrounded enterprise claims:
1. *Outdated against verified state*: The plan ignores already merged work: Technitium HA zone replication via TSIG AXFR + NOTIFY and VRRP-driven single-active promotion is already built ([PR #145, #148, #149]); preempt delay is implemented in `router-ha` ([PR #144]); alerting (Alertmanager + ntfy + Kea hooks) is deployed on `elitedesk` ([PR #150]); and dashboard binding links were already fixed ([PR #146]).
2. *Technical inaccuracies*: The HA section claims that without `conntrackd`, VRRP failover immediately drops all UDP flows and WireGuard tunnels. This is false. WireGuard is stateless UDP and re-establishes roaming NAT state upon the next packet/handshake; outbound UDP creates fresh conntrack entries immediately. Furthermore, claiming `systemctl restart systemd-networkd` drops physical carrier is incorrect (`systemd-networkd` preserves interface carrier state across restarts by default unless `KeepConfiguration=no`).
3. *Blindness to live hardware incident*: The plan treats `elitedesk` as production-ready bare metal, ignoring the open incident where 1–8% of TCP connections lose SYN-ACKs at the X520 (suspected `ixgbe` Flow Director / ATR conflict) and the card previously fell off the PCIe bus.
4. *Fabricated enterprise scope*: The "Two-Tier Vault/Infisical Bootstrap Paradox" is an artificial problem. `clan vars` / `sops-nix` already decrypts host secrets offline from local storage at boot; injecting Vault/Infisical into a two-node homelab router pair is unnecessary LLM hallucination.
5. *Ecosystem citations*: While `chayleaf/nixos-router` and `mdlayher/corerad` are genuine, claims regarding `joshpearce/nix-router`'s specific internal filenames (`network-irq.nix`, vector/ulogd2, unit test harnesses) appear embellished. — [satisfied-conditional: reconcile with live PRs and purge fabricated enterprise solutions]

**Q2 Priorities.** The P1–P4 ordering is structurally flawed for both of the maintainer's goals. 
For Goal 1 (`elitedesk` as primary), hardware stabilization must precede any HA or failover work. Deploying VRRP or promoting `elitedesk` while its X520 drops 1–8% of TCP SYN-ACKs guarantees a degraded network. 
For Goal 2 (community flake), pitching complex, fragile state sync (`conntrackd`) in P1 ahead of basic usability, firewall explainability, and multi-node test harnesses repels rather than attracts users.
The ordering should be:
- **P0: Hardware & Operational Triage**: Fix the X520 Flow Director ATR issue, verify PCIe link stability, and increase the dashboard listen backlog from 5 to 128.
- **P1: Safe Standby Invariants & Promotion**: Deliver `nodeMode`, targeted `networkctl` reloading, and GARP emission so standby nodes cannot leak traffic.
- **P2: Community Core & Observability (Discussion 20 alignment)**: Implement `routerctl` CLI diagnostics, compile-time topology assertions, and automated QEMU VM integration tests.
- **P3: Advanced Features**: CoreRAD, declarative CAKE derivation, and optional netns slicing.
- **P4: State Synchronization (`conntrackd`)**: Defer until manual and basic VRRP failover are proven rock-solid. — [satisfied-conditional: reprioritize hardware stabilization and Discussion 20 invariants ahead of conntrackd]

**Q3 Item verdicts.**
- **Node role modeling (`nodeMode`)**: *Adopt-modified.* Essential to prevent split-brain WAN/broadcast contention, but implement as a composable module profile setting granular sub-flags rather than a monolithic enum that blocks custom topologies.
- **`networkctl-reconfigure` WAN promotion**: *Adopt-modified.* Scoped reloads avoid bouncing unmanaged links, but must be validated in integration tests to ensure DHCPv4/v6-PD reliably re-triggers on physical interfaces without requiring an `ip link down/up` cycle.
- **`conntrackd`**: *Defer.* High maintenance complexity and kernel offload incompatibilities across heterogeneous VM/bare-metal environments; homelab TCP sessions can reconnect, while UDP/WireGuard self-heals.
- **GARP refresh (`arping`/`ndisc6`)**: *Adopt.* Standard, low-risk, and vital for instantly flushing downstream switch and client ARP/NDP tables during VIP failover.
- **IRQ/RPS/XPS pinning**: *Adopt-modified.* Valuable for `elitedesk`'s multi-queue X520, but the blueprint's blanket `all_cores_mask` RPS assignment on top of MSI-X pinning induces cache thrashing; must be disabled on virtualized nodes (`router` under Proxmox).
- **SFP quirk abstraction (`allowUnsupportedSfp`)**: *Adopt.* Clean, typed abstraction over raw `boot.extraModprobeConfig` for `ixgbe` hardware on bare metal.
- **Automatic CAKE**: *Adopt-modified.* Auto-derivation from declared link rates improves community UX, but must preserve explicit user overrides for asymmetrical WAN links.
- **Dashboard privilege separation**: *Adopt.* Clean defense-in-depth pattern (unprivileged UI daemon + root Unix domain socket helper) that eliminates unsafe bind mounts across differing secret backends (`agenix` vs `sops-nix`).
- **SSE/WebSockets**: *Defer.* Polling every 5s is harmless; increasing web server architectural complexity is unjustified while the dashboard's socket backlog remains at 5.
- **Kea/Technitium data planes**: *Adopt-modified.* Exposing leases and metrics enhances the dashboard, but parsing should remain non-blocking so dashboard availability never depends on daemon health.
- **Two-tier secrets (Vault/Infisical)**: *Reject.* Solves an artificial problem; `clan vars` / `sops-nix` already provides zero-network, local offline boot decryption.
- **Network namespace (`netns`) zones**: *Defer.* Increases architectural complexity across firewall boundaries, DNS forwarding, and inter-zone routing; premature before core router modules stabilize.
- **CoreRAD**: *Adopt-modified.* Excellent Prometheus telemetry for IPv6 RA, but keep it an opt-in alternative to `systemd-networkd`'s native engine. — [satisfied]

**Q4 Gaps and next steps.**
The plan misses critical operational realities:
1. *Hardware triage before promotion*: It fails to address `elitedesk`'s active X520 SYN-ACK drop rate (disable Flow Director ATR via `ethtool -K <iface> ntuple off` to verify) or its past PCIe detachment.
2. *Testing strategy*: The plan proposes zero automated verification. It lacks the multi-node QEMU VM test harness agreed upon in Discussion 20 to simulate carrier loss, split-brain WAN leases, and VIP preemption.
3. *Discussion 20 reconciliation*: Discussion 20 prioritized `routerctl` CLI diagnostics, compile-time invariant assertions, and firewall explainability. The plan largely ignores these consensus items in favor of complex state synchronization.
4. *Operational failure modes*: No documentation or runbooks for split-brain recovery, cable modem lockups, or upstream ISP MAC rebinding.

**Immediate Tracked Work (Next 3–5 Items)**:
1. **Resolve `elitedesk` hardware instability**: Test disabling `ixgbe` Flow Director (`ntuple off`), verify PCIe AER logs, and increase `router-dashboard`'s listen backlog from 5 to 128.
2. **Implement safe `nodeMode` abstraction**: Create declarative primary/standby profiles in `router-ha.nix` with evaluation assertions preventing standby nodes from starting Kea, miniupnpd, DDNS, or activating WAN.
3. **Non-disruptive WAN promotion script**: Replace daemon restarts in `notify_master` with targeted `networkctl reload`, `networkctl reconfigure <wan>`, and `arping`/`ndisc6` GARP emissions.
4. **Multi-node NixOS VM integration test**: Build an automated QEMU interactive/headless test verifying dual-router VRRP election, VIP migration, and standby link suppression. — [satisfied-conditional: gate primary promotion on X520 ATR resolution and automated QEMU failover tests]

### Claude

I read `modules/router-ha.nix` (lines 72–91, 144–147, 196–203, 274–279). Shell access was refused, so the other repo claims below rest on the verified state you gave me, and I could not check any external repository.

**Q1 Accuracy and provenance.**
- **Correct:** `notify_master` does run `systemctl restart systemd-networkd` (`modules/router-ha.nix:80`).
- **Wrong:**
  - Both documents give `conntrackd -C` as the commit command. `-C` sets the config file path; the commit flag is `-c`.
  - The blueprint's `if [ -x ...conntrackd ]` test is always true, because the store path is baked in at build time.
  - The blueprint adds `set -euo pipefail` to `notify_master`. One failed `ip` or `networkctl` call would then skip starting the single-active units, which is worse than today.
  - "RFC 9686 IPv6-Only Preferred" is wrong. IPv6-Only Preferred is RFC 8925 (a DHCPv4 option), not an RA feature.
  - "NixOS gives 100% bit-identical builds" is false.
  - "Identical protocol logic" for CARP and VRRP is false. They share IP protocol 112 but have different packet formats and authentication.
  - "All IRQs hit CPU 0 by default" does not match ixgbe or igc, which use MSI-X with one queue per CPU, usually with irqbalance.
- **Outdated:**
  - The matrix marks HA as "VRRP + shell ⚠️". It ignores `preemptDelay` (#144), Technitium zone HA (#145/#148/#149), alerting (#150) and the existing `keaSync` option.
  - The diagram shows the 10.10.10.1 VIP as live. VRRP is not enabled on the pair.
- **Likely fabricated or unverifiable:**
  - `sdlfoundation/hard-nix-router` looks invented.
  - `joshpearce/nix-router` and its `network-irq.nix` are unverifiable.
  - chayleaf's repository is real, but the "full netns isolation" claim about it needs checking.
  - The numbers have no source: "~3-4 Gbps per core", "single-digit CPU at 10G", "30 lines of overrides".
  - The April 2026 conntrackd ledger and the commit `8a8d1b1167c1` need checking against the unified-nix-configuration repo.
- **Overstated:** "Every TCP session drops on failover" ignores `nf_conntrack_tcp_loose`. In practice the bigger outage is the new master getting a WAN DHCP lease and the IPv6 prefix again, which neither document mentions.
- **Inconsistent topology:** the doc says router has igc NICs passed through to the VM. But the `enp6s16`/`enp6s17` names and the locally administered `02:` MACs look like virtual NICs. Someone should check this, because it changes the IRQ advice and the VRRP-over-bridge behaviour.

**Marker:** [satisfied-conditional: both documents are marked "unverified research" and corrected before merge; the external repositories are checked by someone with network access]

**Q2 Priorities.**
The ordering is wrong for goal 1. The plan never mentions the open X520 incident. A card that drops 1-8% of TCP SYN-ACKs and once fell off the PCIe bus cannot be the primary router, whatever the HA features.

- **P0 – hardware gate:** test with Flow Director ATR off (`ethtool --set-priv-flags <if> flow-director-atr off`, or turn on ntuple). Watch for PCIe AER errors, firmware problems and link flaps, and alert on them. Set a soak acceptance threshold. If the card fails, replace it.
- **P1 – failover correctness:**
  - Fix WAN promotion.
  - Add a two-node NixOS VM test.
  - Write a rehearsal runbook covering WAN lease, prefix, Kea, Technitium HA and alerting.
  - Fix the dashboard listen backlog of 5.
- **P2:** typed single-active ownership, and a decision on the DHCP HA model.
- **Later:** conntrackd, performance tuning and dashboard work. Community-facing features (netns, CoreRAD) come after the docs are honest.

**Marker:** [satisfied]

**Q3 Item verdicts.**
- **Node role modeling: adopt-modified.** `role` and `singleActiveUnits` already exist. A static `nodeMode` that disables Kea, DDNS and RA at build time breaks promotion. What's needed is typed per-service ownership tied to the VRRP state, following the `zoneReplication.ha` pattern.
- **`networkctl reconfigure` WAN promotion: adopt-modified.** If the WAN `.network` file says `ActivationPolicy=always-down`, `reconfigure` reapplies that and takes the link back down. Use `ActivationPolicy=manual` with `networkctl up`/`down`, and test it in a VM.
- **conntrackd: defer.** It only helps once VRRP failover works and is rehearsed. The new master still has to get a WAN lease, which outlasts most flow timeouts that matter. The router side of the sync link is a virtual NIC (`ens18`) on a VM. Rebuild it from the real `primary-backup.sh` flow (`-c`, `-f`, `-R`, `-B`), not this blueprint.
- **GARP refresh: adopt-modified (small).** Keepalived already sends gratuitous ARP on transition (`vrrp_garp_master_*`). At most, expose `garp_master_refresh` as an option. Don't add `arping`.
- **IRQ/RPS/XPS pinning: defer.** It interacts with ATR, which is the suspected cause of the incident, so close the incident first. It is meaningless for virtio NICs in the VM. The blueprint ignores irqbalance and NUMA, and its `1 << idx` mask breaks above 64 CPUs. If added later, make it opt-in and per-interface.
- **SFP quirk abstraction: reject.** The typed option would just wrap `boot.extraModprobeConfig`. Document the setting instead.
- **Automatic CAKE: adopt-modified.** Derive the shaper rate from a declared measured rate × 0.9, never from link speed.
- **Dashboard privilege separation: adopt.** Remove the hard-coded `/run/agenix` path first, then split the privileged parts out (most likely `DynamicUser` plus a small root helper).
- **SSE/WebSockets: defer.** Polling every 5 seconds is not a real problem. Fix the backlog first.
- **Kea/Technitium dashboard data: adopt-modified.** Read leases through Kea's control socket, not the memfile. Check `.status == "ok"` on every Technitium call.
- **Two-tier secrets: adopt as documentation only.** This is just the existing sops/clan-vars model. No Vault integration.
- **netns zones: defer.** It is costly and changes firewall semantics. Treat it as a design discussion for the community goal.
- **CoreRAD: defer.** Check that upstream is still maintained first. A metrics exporter for networkd's RA output may be enough.

**Marker:** [satisfied]

**Q4 Gaps and next steps.**
What the plan misses:
- **Testing:** two-node NixOS VM tests for promotion, demotion, the fault path and service ownership. This is item Q5 of discussion 20.
- **Failover rehearsal:** measured outage time, live supervised drills, and a written rollback plan.
- **Hardware validation:** a SYN/ACK loss soak test at the X520, PCIe and link alerts in router-alerting, and firmware and kernel version pinning.
- **Upgrade safety:** upgrade one node at a time, with VRRP pinned and the backup upgraded first. Clan's `machines update` does not give deploy-rs magic rollback, so don't assume it.
- **Security:** the VRRP password defaults to `nix-router-ha` (`modules/router-ha.nix:146`). It is PASS auth and ends up in the world-readable Nix store (`:276-279`).
- **DHCP HA:** the `keaSync` option (`:196`, which opens port 8000) contradicts the "single-active, manual promotion" model. Decide which model is real.
- **VM versus bare metal:** VRRP needs the Proxmox bridge to pass multicast and the backup's MAC. VM NIC tuning does not carry over to the X520.

**Reconciling with discussion 20:** don't run a parallel roadmap. Treat this plan as input to discussion 20, item by item. Discussion 20's maturation freeze, VM-test matrix and safety assertions take precedence. New feature work (netns, CoreRAD, SSE, conntrackd) waits behind that freeze.

**Track now:**
1. **X520 incident closeout.** Test with ATR off, alert on AER and link flaps, run a soak test with acceptance criteria. If it fails, replace the NIC.
2. **Fix router-ha WAN promotion.** No networkd restart, check the `ActivationPolicy` interplay, plus a two-node VM eval and runtime test.
3. **Failover rehearsal runbook and one supervised live drill.** Measure the WAN lease and prefix time, and cover the Technitium HA, Kea and alerting paths.
4. **Typed single-active ownership and the DHCP HA decision.** Retire `keaSync` or make it real. Move the VRRP auth secret out of the Nix store.
5. **Docs honesty and the dashboard backlog.** Correct or label both documents, and raise the listen backlog above 5.

**Marker:** [satisfied-conditional: item 1 has a pass/fail threshold that gates any VRRP enablement]

### GitHub Copilot

**Q1 Accuracy and provenance.** Confirmed accurate: `modules/router-ha.nix:80` really calls `systemctl restart systemd-networkd` in the master hook, and `preemptDelay` really exists (line 156+) — so the plan's core P1 complaint is true, but it understates that delayed fail-back already exists (#144), making it sound like HA is more primitive than it is. Likely fabricated/unverifiable: the entire external-repo survey (`chayleaf/nixos-router`, `joshpearce/nix-router`, `sdlfoundation/hard-nix-router`) and the "April 2026 conntrackd-flowtable DECISION.md … commit `8a8d1b1167c1`" — these read as plausible-sounding but unverified/likely-invented citations; treat every external repo name, commit hash, and "industry standard" claim as needing a live link check before quoting. The feature matrix's checkmarks for those repos are unverifiable the same way. The elitedesk ixgbe PCIe-fall-off incident and 1-8% SYN-ACK loss are real per the prompt's verified state, but the plan never mentions them — a significant gap, not an error, but it means the plan's confident P1/P2 ordering was written blind to the actual open incident. "No live failover yet" (verified state) contradicts the plan's implicit tone that conntrackd is the last missing piece before a safe cutover — VRRP itself is unrehearsed live, which is a bigger gap than conntrackd.

**Q2 Priorities.** Wrong for right now. P1 (HA primitives) is right directionally but is sequenced ahead of diagnosing the SYN-ACK/X520 incident, which is backwards: promoting elitedesk to primary while ~1-8% of TCP SYN-ACKs silently vanish at the NIC is unacceptable regardless of how good VRRP/conntrackd get. Hardware validation must precede HA work. P3 (dashboard) and P4 (secrets two-tier) are correctly low priority but for the wrong reason — the plan treats them as polish; they're actually fine to defer because they don't touch failover safety at all. Correct order for the stated goals: (0) root-cause the X520 SYN-ACK loss, (1) rehearse VRRP failover live on the homelab pair without new features, (2) non-disruptive WAN promotion + GARP (cheap, high-value, already-diagnosed problem), (3) conntrackd (valuable but only after bare VRRP is proven), (4) performance/dashboard/secrets.

**Q3 Item verdicts.**
- Node role modeling (`nodeMode`): adopt-modified — useful abstraction, but implement as assertions/mkIf wiring, not a rename of what `router-ha`/`zoneReplication.ha` already does; audit overlap with #145/#148/#149 first.
- networkctl-reconfigure WAN promotion: adopt — directly fixes a verified real bug (full networkd restart drops LAN/mgmt); low risk, do before conntrackd.
- conntrackd: adopt-modified — real gap, but gate behind a live failover rehearsal; FTFW over the mgmt link is sound, don't let the unverifiable "DECISION.md" backstory drive the design.
- GARP refresh: adopt — cheap, standard, pairs naturally with WAN promotion fix.
- IRQ/RPS/XPS pinning: adopt-modified — worth doing on elitedesk (bare metal, X520), but do it *as part of* investigating the SYN-ACK loss (Flow Director/ATR interacts with RSS/IRQ steering), not as a separate P2 performance item; on the Proxmox VM `router` this has little value (virtio/passthrough queue counts differ) — don't generalize the module blindly across VM vs bare metal.
- SFP+ quirk abstraction: adopt — trivial, host-specific, zero risk, already needed by elitedesk.
- Automatic CAKE: defer — nice ergonomics, no HA/reliability payoff, not urgent for either goal.
- Dashboard privilege separation: adopt-modified — good hygiene and fixes the sops/agenix path assumption bug, but scope it to the privilege-split only; skip inventing new widgets until core HA is proven.
- SSE/WebSockets: defer — cosmetic relative to current goals.
- Kea/Technitium data-plane widgets: defer — nice-to-have, not blocking either goal.
- Two-tier secrets (Vault/Infisical): defer — elitedesk/router don't currently need a secrets manager beyond sops/agenix; this is speculative architecture for infrastructure that doesn't exist yet. Revisit only if a real Vault/Infisical adoption is planned.
- netns zones: defer — interesting for community appeal, but adds complexity and failure surface while the VM/bare-metal pair hasn't even done one live failover; also unverified against `router-zones.nix`'s actual current isolation model.
- CoreRAD: defer — valid idea for observability-focused community reputation, but unrelated to both homelab goals; low priority.

**Q4 Gaps and next steps.** The plan has zero testing/rehearsal strategy for the one thing that matters most: a supervised live VRRP failover between `router` and `elitedesk` with rollback criteria — this must exist before any P1 code lands. It omits the open X520 SYN-ACK incident entirely, which is a glaring gap since the plan proposes making elitedesk primary while that's unresolved; any "automatic promotion" work should be blocked on root-causing or mitigating that incident. It conflates aspirational design docs with implemented reality (conntrackd, two-tier secrets) without flagging them as unimplemented, which is a docs-honesty problem — the finished prose reads as though these exist. It doesn't reconcile with discussion 20's framework (positioning, assertions, CLI diagnostics, core decoupling, VM integration tests) at all — these two new docs should be merged into or cross-referenced against discussion 20 rather than left as a parallel roadmap, or maintainers will have two competing priority lists. Recommended tracked items now: (1) X520 SYN-ACK root-cause investigation (router-diag read-only checks + ethtool/ATR stats), (2) non-disruptive WAN promotion + GARP fix in `router-ha.nix`, (3) a documented, supervised live-failover rehearsal plan/checklist, (4) SFP+ quirk option for elitedesk, (5) reconcile this plan's P1–P4 against discussion 20's Q1–Q6 into one roadmap doc, explicitly marking unverified external claims as "unverified" until checked.

[satisfied-conditional: reorder so hardware root-cause (X520 SYN-ACK loss) and a supervised live VRRP failover rehearsal precede any HA feature work (conntrackd, networkctl promotion, IRQ tuning), and strip/flag all unverifiable external-repo and commit-hash citations before this plan is used as a work-item source]

### DeepSeek

**Q1 Accuracy and provenance.** Several claims are wrong or unverifiable. (a) The comparison says CARP and VRRP are "identical protocol logic"; they are not — CARP is OpenBSD-derived, proto 112, with different election/security semantics than RFC 5798 VRRP. (b) "There is no technical feature in CARP/pfsync that Linux cannot deliver with VRRP/conntrackd" is an overclaim; pfsync has different failure modes and conntrackd FTFW has known offload/IPS_OFFLOAD issues (the plan itself cites one). (c) The "April 2026 decision ledger" with commit `8a8d1b1167c1` and the `IPS_OFFLOAD` bit story are unverifiable from the verified state and read as fabricated specifics; treat as suspect until the ledger is linked. (d) The repo names `joshpearce/nix-router`, `sdlfoundation/hard-nix-router`, and the feature matrix entries ("Vector + ulogd", "Pure Nix unit tests", "explicit IRQ affinity") are unverified; the matrix is presented as fact without citations. (e) "64 MSI-X queues" on X520-2 is wrong (X520 is 82599, typically 64 combined but not 64 RX queues; the "saturates at 3-4 Gbps on one core" number is unsourced). (f) The claim that `router-ha` currently does `systemctl restart systemd-networkd` in `notify_master` is not in the verified state and may be stale. (g) The plan ignores the open X520 SYN-ACK loss incident and the PCIe fall-off — the single most important hardware fact for goal (1). (h) "FastTrack flowtables bypass Netfilter" is roughly right but the "single-digit CPU utilization at 10 Gbps on i7-3770" is unsourced. (i) The diagram's "Media Converter Switch" and MACs are plausible but unverified; don't act on them without checking `ip -br link` on both hosts. (j) The comparison's "OPNsense rollback requires ZFS snapshot or reinstall" is outdated — OPNsense has had config backup/restore and BE snapshots for years.

**Q2 Priorities.** The P1-P4 ordering is wrong for the maintainer's goals. Goal (1) is "elitedesk can safely become primary router." That is blocked by the X520 SYN-ACK loss and the PCIe fall-off, not by conntrackd or GARP. Correct order: (P0) hardware validation and incident closure on elitedesk's X520 — disable Flow Director ATR, test with `ethtool -K`, check `dmesg` for AER, run a soak; (P1) failover rehearsal with VRRP actually enabled on the homelab pair, with a documented rollback; (P2) node-role modeling and non-disruptive WAN promotion (these are prerequisites for safe rehearsal); (P3) conntrackd and GARP (nice-to-have; without them failover drops sessions but is still safe); (P4) performance tuning, dashboard, secrets, netns, CoreRAD. The plan puts conntrackd in P1 and hardware validation nowhere — that inverts the risk.

**Q3 Item verdicts.**
- Node role modeling (`primary`/`standby`): **adopt-modified** — good idea, but the plan's "auto-disable 30 lines" must be assertions plus explicit opt-in, not silent defaults; VM `router` vs bare-metal `elitedesk` differ in link naming and driver behavior.
- `networkctl reconfigure` WAN promotion: **adopt** — strictly better than restarting networkd; verify on both hosts, and keep a fallback because `networkctl reconfigure` on a link with `ActivationPolicy=always-down` needs testing.
- conntrackd: **defer** — valuable but the plan's own ledger says it was paused for a real bug; do not ship before failover rehearsal works without it. Also VM↔bare-metal conntrackd sync across the mgmt subnet needs a security review.
- GARP refresh: **adopt** — cheap, low risk; use Keepalived `garp_master_refresh` rather than ad-hoc `arping` where possible.
- IRQ/RPS/XPS pinning: **defer** — do not tune IRQs on a NIC with an open SYN-ACK loss incident; tuning can mask or worsen it. Fix the incident first, then measure.
- SFP quirk abstraction: **adopt-modified** — the option is fine, but `allow_unsupported_sfp=1` is already set on elitedesk; the abstraction should also cover `ixgbe` AER/PCIe recovery, not just SFP.
- Automatic CAKE: **defer** — auto-deriving from declared bandwidth is fine, but the plan ignores that CAKE on a 10G X520 with the current incident is premature; also VM `router` has different shaping characteristics.
- Dashboard privilege separation: **adopt** — the `226/NAMESPACE` failure and `/run/agenix` hardcoding are real; split is correct. Note the listen backlog of 5 is a separate bug to fix now.
- SSE/WebSockets: **defer** — cosmetic; polling at 5s is not the bottleneck.
- Kea/Technitium data planes: **adopt-modified** — read-only widgets via Kea Control Agent and Technitium API, not parsing memfile directly (memfile is an implementation detail and can change).
- Two-tier secrets: **adopt** — the bootstrapping-paradox argument is sound and matches the Clan migration; but the plan's Vault/Infisical framing is overkill for a homelab — `clan vars` + sops is enough.
- netns zones: **defer** — high complexity, VM vs bare-metal differences, and no current threat model justifying it.
- CoreRAD: **defer** — observability is nice, but replacing `IPv6SendRA` is a behavior change during an HA migration; revisit after failover is stable.

**Q4 Gaps and next steps.** The plan misses: (1) the open X520 incident and PCIe fall-off — no hardware validation section at all; (2) a failover rehearsal plan with success criteria, rollback, and observation window; (3) upgrade safety for the Clan migration (`deploy-rs` rollback is asserted, not tested); (4) docs honesty — the comparison reads as marketing, not engineering, and should be retitled "positioning note" or heavily caveated; (5) reconciliation with discussion 20, which already converged on assertions, `routerctl` diagnostics, core decoupling, and QEMU VM tests — the new plan duplicates some of that and contradicts the "maturation freeze" by proposing a large new roadmap. Reconcile by folding the new items into discussion 20's work items rather than creating a parallel plan. Track now: (a) close the X520 SYN-ACK incident (Flow Director ATR off, soak test, PCIe AER check); (b) enable VRRP on the homelab pair and run a supervised failover rehearsal with rollback; (c) implement `nodeMode` + `networkctl reconfigure` WAN promotion with eval assertions; (d) fix dashboard listen backlog and `/run/agenix` hardcoding; (e) rewrite the comparison doc with citations or downgrade it to a positioning note. [satisfied-conditional: hardware incident closure and failover rehearsal must precede conntrackd, IRQ tuning, and netns work]

### Synthesis — Q21

**Q1 Accuracy.** The plan is useful, but it is outdated and was written
without knowing about the hardware incident. Corrections everyone accepted:

- **Outdated:** it ignores #144–#150 and still shows the VIP as live, but VRRP
  is not enabled.
- **Missing the incident:** it never mentions the X520 reply-loss or PCIe
  incidents.
- **Wrong:**
  - conntrackd commit is `-c`, not `-C`;
  - IPv6-Only Preferred is RFC 8925, not RFC 9686;
  - CARP and VRRP are analogous, not identical (VRRPv3 is RFC 9568);
  - "100% bit-identical builds" is false;
  - "all IRQs on CPU0" doesn't match ixgbe or igc behaviour;
  - "every session drops without conntrackd" overstates it (TCP loose
    pickup, UDP and WireGuard re-establish themselves).
- **Unsourced:** the performance numbers (3–4 Gbps per core, single-digit
  CPU at 10G).
- **Citations:** see the IC fact-check; the repositories and the ledger are
  real.

Marker: [satisfied-conditional: both documents are corrected and labelled
"research input; unverified where marked" before anyone uses them as a work
source.]

**Q2 Priorities.** All five voices agree:

- **P0, hardware gate:** the X520 incident closes against a pass/fail
  threshold before VRRP is enabled or elitedesk is promoted.
- **P1, failover correctness:** non-disruptive WAN promotion, a two-node VRRP
  VM test, a rehearsal runbook and one supervised drill.
- **Later:**
  - conntrackd, performance tuning, dashboard features;
  - community features (netns, CoreRAD), once the docs are honest.

The plan feeds discussion 20's roadmap instead of competing with it.
Marker: [satisfied].

**Q3 Item verdicts** (majority, with the deciding argument):

| Item | Verdict | Why |
| --- | --- | --- |
| Node role modeling | adopt-modified (5/5) | Typed per-service ownership tied to VRRP state, following the `zoneReplication.ha` pattern. A static `nodeMode` that disables Kea, DDNS and RA at build time would break promotion |
| `networkctl reconfigure` WAN promotion | adopt-modified (5/5) | Removes the networkd restart. `ActivationPolicy=always-down` conflicts with `reconfigure`, so use `manual` with `networkctl up`/`down`. Prove it in the VM test and on the pinned systemd |
| conntrackd | defer (4/5) | Only valuable once plain VRRP failover is rehearsed; rebuild from the April decision, not the blueprint |
| GARP refresh | adopt-modified (3/5) | Use Keepalived's own `vrrp_garp_*` and `garp_master_refresh` settings; no `arping` or `ndisc6` scripts |
| IRQ/RPS/XPS pinning | defer (3/5) | It interacts with Flow Director, the incident's suspect, and means nothing for virtio. Revisit after the incident, opt-in and per interface |
| SFP quirk abstraction | defer (split) | Document `allow_unsupported_sfp`; a typed wrapper adds little |
| Automatic CAKE | defer (split) | If ever built, derive the rate from a declared, measured rate, never from link speed (5/5 on that point) |
| Dashboard privilege separation | adopt-modified (5/5) | Audit the existing privileged units, remove secret-path assumptions, fix the listen backlog now (`nch-sny.35`) |
| SSE/WebSockets | defer (5/5) | 5 s polling isn't the bottleneck |
| Kea/Technitium data planes | adopt-modified (4/5), low priority | Use Kea's control socket and Technitium's API (`.status` checked), not the memfile |
| Two-tier secrets | reject the Vault framing; document only | The existing `*File` options plus agenix, sops or clan vars already decrypt offline at boot |
| netns zones | defer (5/5) | No threat model yet; it changes firewall semantics |
| CoreRAD | defer (4/5) | A behaviour change during the HA migration; check upstream is maintained first |

Marker: [satisfied].

**Q4 Gaps.** What the plan misses:

- **Tests:** two-node VRRP VM tests extending the existing harness (promote,
  demote, fault, zone HA, single-active units).
- **Rehearsal:** a runbook with measured outage (WAN lease and prefix time),
  abort criteria and tested failback.
- **Hardware qualification:** a threshold, plus AER and link-flap alerts.
- **Upgrade safety:** one node at a time, backup first. Clan's
  `machines update` does not give magic rollback.
- **Security:** VRRP authentication is a store-visible default password.
- **Model honesty:** `keaSync` contradicts the single-active DHCP model.
- **Docs honesty** for both documents.

Marker: [satisfied-conditional: the hardware gate precedes any VRRP
enablement].

**Tracked work** (beads):

- In nix-router-optimized (`router-*`): WAN promotion without networkd
  restart, two-node VRRP VM test, VRRP auth secret as a file, single-active
  ownership and the `keaSync` decision, Keepalived GARP options, correcting
  and labelling the two documents.
- In nix-clan-homelab: a supervised failover rehearsal gated on `nch-sny.34`
  and `nch-sny.31`, and a pass/fail threshold for the X520 gate.
