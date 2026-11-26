## Discussion 23: Clan integration through Clan's inventory, and what would attract users

**Status:** closed (round 1 plus a narrowed follow-up).
**Date:** 2026-11-25
**IC:** Claude (Claude Code session leading the round)
**Subject:** whether nix-router-optimized should integrate with
[clan-core](https://docs.clan.lol) through Clan's inventory (machines, tags,
service instances, roles, exports); whether that is advisable; whether it
would make the flake more attractive to the NixOS community.
**Roster:**
- Codex (`codex exec`, read-only sandbox)
- Gemini (`agy -p`)
- Claude (`claude -p`)
- Copilot (`copilot -p`; its round 1 answer is headed "Claude's
  position", which is how the CLI signed it, not a second Claude seat)
- DeepSeek (direct API, `deepseek-flash`)
- OpenCode enrichment seat (`opencode/big-pickle`)

Full quorum in both rounds. Raw answers are in the appendix.

### Context given to every voice

Verified on 2026-11-25:
- **This flake:** about 55 `services.router-*` modules. Its pitch is a typed
  topology model with derived nftables, Kea, DNS and dashboard, plus
  evaluation-time assertions. It has 0 GitHub stars and one known consumer.
  It is secret-backend agnostic (`*File` options).
- **The consumer (nix-clan-homelab):** Clan for machine lifecycle, den for
  composition, and a typed `homelab.hosts` fleet inventory. A 987-line
  `router-role` aspect maps that inventory onto this flake's options. Kea
  reservations and DDNS settings still come from unified's `lib/hosts.nix`.
- **Clan's inventory model:** `clan.service` modules with roles, settings
  and per-instance configuration. Other flakes can export services as
  `clan.modules."@author/name"`. Exports are experimental. clan-core's
  GitHub mirror shows 182 stars; chayleaf/nixos-router has 417.
- **Four candidate shapes:**
  1. a native `clan.service` in this flake;
  2. an optional adapter;
  3. consumer mapping plus generic options moved upstream;
  4. this flake's inventory as the source for Clan.

### First-pass convergence (round 1)

All six voices agreed:

1. **Fit.** VRRP pairing (membership, priority, preempt, which credentials
   the master needs), Kea HA peering and monitoring targets genuinely span
   machines and match Clan roles. Interface and zone topology, nftables,
   CLAT/NAT64, hardening, daemon internals, the dashboard and the
   evaluation-time assertions stay single-host NixOS options. The typed
   topology is the product; splitting it across Clan settings would lose the
   one place invariants are checked.
2. **Shape: 3 now, 2 later, 1 only on demand.** Move generic HA and standby
   logic from the consumer into plain options with VM tests (helps every
   user, no Clan coupling, testable with plain `nixosTest`). An optional
   adapter can follow; a native `clan.service` would tie this flake's API to
   a young framework and its experimental exports, for an audience of one.
3. **Reject shape 4.** A router framework should not own the fleet.
   Codex alone allowed it where network inventory already is the fleet
   authority.
4. **Not now.** First: generic HA options upstream, the consumer off the
   predecessor repo, a stable reservation input schema.
5. **Community.** Clan support would interest Clan users, a small group,
   and is not a top-three adoption lever.

### IC fact-check (between rounds)

The round 1 context left out facts that changed the community answers:

- **Examples and tests already exist.** `examples/` has a single router, an
  HA pair and five more. More than 30 tests in `tests/` are wired into
  `checks`, including `router-ha-lab`, `router-ha-ownership`,
  `router-ha-vrrp-auth` and `doc-examples`. Every voice's round 1 top
  recommendation assumed they were missing.
- **Nothing makes them visible.** Git tags go up to `v0.10.0`, but there
  are no GitHub Releases, no top-level changelog and no repository topics,
  and the README does not point to a quickstart or the examples near the
  top.
- **`services.router-ha` already covers the basics:** role, VIP, VRID,
  password file, priority, preempt delay, `singleActiveUnits`, WAN takeover
  with health checks, transition scripts and the Kea HA peer.
- **What the consumer's `router-role` still carries:**
  - the inventory mapping;
  - a manual-failover specialisation;
  - standby guards;
  - an abort fence;
  - MASTER-only units (Pangolin, gerbil);
  - a Technitium zone-HA owner;
  - NIC and SFP alert rules;
  - credential gating by mode.
- **Decision 11's "single authority" means the consumer's fleet host
  list,** not an inventory inside this flake. DeepSeek and Copilot read it
  the other way in round 1.
- **`services.router-security-hardened` already exists.** The consumer does
  not enable it because it forces strict `rp_filter`.

### Narrowed follow-up

| Question | Result |
| --- | --- |
| Adoption gap | All six: **visibility and trust, not more content.** GitHub Releases from the tags, a changelog and a stated stability policy; a README that opens with the typed-topology differentiator and a quickstart linking `router-single-basic.nix` and `router-ha-pair-example.nix`, saying they are covered by the HA VM tests; a CI badge; repository topics; a NixOS Discourse post. Gemini also counted making `rp_filter` configurable as an adoption fix. |
| What moves upstream | Agreed by all six: **standby guards** (keep WAN down, list units that must not run on a standby). All six in substance (Gemini as "standby fencing"): an **abort fence** as a generic "refuse to promote" hook. Five (not Copilot): **generic MASTER-only unit ownership** beyond `singleActiveUnits`, with the Pangolin and gerbil wiring itself staying in the consumer. Agreed by every voice that addressed F4: a **configurable `rp_filter`** in `router-security-hardened`. Stays in the consumer: the `homelab.hosts` mapping; NIC and SFP alert thresholds (OpenCode would add hardware-neutral alert hooks upstream). |
| Still split | **Manual-failover specialisation:** Claude and Copilot upstream (an opt-in cold-standby mode); Codex, DeepSeek and OpenCode keep it in the consumer as a site runbook. **Credential gating by mode:** Claude and DeepSeek upstream; the other four keep it. **Technitium zone-HA owner:** DeepSeek and OpenCode want a generic "current role" signal upstream; Claude would expose only the role-file path; the others keep it. |
| Second consumer | All six: **none needed to prototype an adapter inside the consumer; one independent consumer needed before publishing a maintained upstream adapter.** Generic HA options need no second consumer; VM tests are their proof. |
| Reservations and DNS authority | All six: author them in the **consumer's fleet inventory**. Five: this flake accepts plain typed inputs (`router-dhcp` staticLeases, `router-kea` reservations, DNS-zone records) and defines no host-inventory schema of its own. DeepSeek wanted this flake to accept a typed host list and derive those options itself; the others put that mapping in the consumer or an optional `lib/` helper. |

### Closure

**Is Clan integration advisable?** Not now. Revisit it as an optional
adapter once the generic HA options exist and a second Clan user appears.

**Would it make the flake more attractive?** Only to existing Clan users,
and only slightly. What holds adoption back is that the existing examples,
tests and tags are invisible to an outsider.

**Do now, in this repo:**
1. **Visibility.** GitHub Releases from the existing tags, a changelog and a
   stability policy for option names. A README that opens with the
   differentiator and a quickstart pointing to the existing examples and the
   VM tests that cover them. A CI badge and repository topics. Then a NixOS
   Discourse post.
2. **Generic HA options.** Standby guards, an abort fence and generic
   MASTER-only unit ownership, each with a VM test extending the `router-ha-*`
   checks.
3. **`router-security-hardened`.** Make `rp_filter` configurable, so a
   consumer that needs loose filtering can enable the rest. Its companion
   items (`install <mod> false` instead of blacklist only, `bpf_jit_harden`,
   `suid_dumpable`) are listed in nix-clan-homelab PR #61.

**In the consumer (nix-clan-homelab):**
- Author Kea reservations and DDNS settings in `homelab.hosts`, no longer
  in unified's `lib/hosts.nix` (bead `nch-a9a.6`).
- Shrink `router-role` as the upstream options land.
- A Clan adapter prototype may live there; publishing it upstream waits for
  a second consumer.

Beads: `router-r6t` (visibility), `router-4gf` (generic HA options), `router-mwb` (`router-security-hardened`); in nix-clan-homelab, `nch-a9a.6` and `nch-sny.41`.

---

## Appendix: prompts and raw answers

Answers are verbatim. Not every claim in them was verified; the IC fact-check above takes precedence.

### Round 1

<details>
<summary>Round 1 prompt</summary>

ROUNDTABLE: Should nix-router-optimized integrate with Clan through Clan's inventory, and would that make it more attractive to the NixOS community?

You are one voice in a multi-agent design discussion (Codex, Gemini, Claude, Copilot, DeepSeek). Answer independently. Do not run shell commands or edit files. If you cite a fact you cannot verify, say it is unverified. Keep the answer under 1200 words.

## Context (verified by the discussion leader on 2026-11-25)

**nix-router-optimized** (public on GitHub, MIT, created 2026-03, 591 commits, 0 stars, docs site, one maintainer who is also its only known consumer). A modular NixOS router framework: about 55 NixOS modules (`services.router-*`: networking, zones, firewall/nftables, Kea DHCP, Technitium DNS, VRRP via keepalived `router-ha`, dashboard, alerting, VPNs, CLAT/NAT64, hardening). Its pitch is a typed topology model (interfaces, subnets, zones) from which nftables, Kea reservations, DNS and dashboards are derived, with evaluation-time assertions. Its dashboard builds a read-only "inventory" artifact (subnets, hosts, reserved addresses, interfaces, prefixes, edges) derived from the router's own config: DHCP reservations, Kea and Technitium settings. Earlier discussions in that repo (11, 12) decided the repo-native host inventory stays the single authority (no phpIPAM), improved with generated views. It knows nothing about Clan; secrets are plain `*File` options so agenix, sops or clan vars all work.

**nix-clan-homelab** (the consumer). Uses clan-core for machine lifecycle (install, facter, vars, SSH CA, `clan machines update`) and den aspects for composition. It has its own typed fleet inventory `homelab.hosts` (addresses, roles, SSH targets, appliances like cameras and APs, and per-router attributes: mode lone/primary/vrrp, WAN identity, VRRP priority and preempt delay). A `router-role` aspect of 987 lines translates that inventory into nix-router-optimized options: VRRP pairing between two routers (elitedesk bare metal, router a Proxmox VM), which credentials the master needs, Kea HA, standby behaviour. Kea DHCP reservations and DDNS settings are still read from the predecessor repo's `lib/hosts.nix`. Clan's own inventory gets machine tags from `homelab.hosts` roles.

**Clan's inventory model** (clan-core 26.05). `inventory.machines` (with tags) and `inventory.instances.<name> = { module = { name; input; }; roles.<role>.machines/tags; settings; }`. Services are `clan.service` modules with roles, `perInstance`/`perMachine` config, and access to the other role members. Any flake can export services as `clan.modules."@author/name"` for others to use with `module.input = "<flake input>"`. "Exports" (experimental) let a service publish structured data (addresses, endpoints) to other machines and instances. Clan ships services such as sshd, borgbackup, monitoring (experimental), wireguard, zerotier, dyndns, coredns, certificates. clan-core's GitHub mirror shows 182 stars; development happens on git.clan.lol. For comparison, chayleaf/nixos-router has 417 stars.

**Candidate integration shapes** (non-exhaustive):
1. Export a `clan.service` from nix-router-optimized, e.g. roles `router` (lone/primary/backup via VRRP, priority as settings) and `lan-member` (hosts that get a DHCP reservation and DNS record from their inventory entry), with exports carrying addresses to the routers.
2. Keep the router flake Clan-agnostic; ship an optional adapter (separate flake or `contrib/clan/`) that maps a Clan inventory to router options.
3. Do nothing in the router flake; keep the mapping in each consumer (today's 987-line `router-role`), perhaps slimmed by moving generic parts (VRRP pairing, standby safety) upstream as plain NixOS options.
4. Make the router's typed host inventory the source that both the router and Clan consume (inverse direction).

## Questions (mark each with exactly one of `[satisfied]`, `[satisfied-conditional: X]`, `[needs more evidence: X]`)

Q1. Fit. Which router concerns genuinely span machines and suit Clan's roles/instances/exports (e.g. VRRP pairs, DHCP reservations and DNS for fleet hosts, credentials for the master, monitoring targets), and which must stay single-host NixOS options?

Q2. Shape. Compare shapes 1-4 on: coupling to a young, fast-moving framework; benefit to non-Clan users; reduction of consumer glue; testability (VM tests without Clan); maintenance for one maintainer.

Q3. Advisability. Should this be done now, later, or not at all? What has to be true first (for example: generic HA and standby options upstream, the consumer no longer reading the predecessor repo, a second consumer)?

Q4. Community. Would Clan integration make the flake more attractive to the NixOS community, or is adoption limited by other things (zero stars, single consumer, documentation, examples, VM tests, stability, naming)? Name the 3 changes most likely to attract users, in order.

</details>

<details>
<summary>Codex</summary>

**Make Clan an optional integration. Start by moving reusable HA behavior into the router modules, then use the homelab to validate an adapter.** Clan can make a router pair easier to deploy as part of a fleet. I’d expect that to matter mainly to existing Clan users. For the wider NixOS community, a working standalone example and tested failover are more persuasive.

### Q1. Fit [satisfied]

Clan is a good fit for decisions that require knowing **which machines participate and how they relate**. A router instance can identify the peers in a VRRP pair, associate fleet hosts with a LAN, and nominate monitoring targets. Clan vars can provision credentials to the machines that may need them. In particular, if a backup needs a credential after promotion, it needs that credential before failover.

The router modules should own the **meaning and enforcement** of that input. This includes interface bindings, subnet and zone definitions, nftables policy, Kea and DNS configuration, VRRP priorities and timers, and what the standby may do before promotion. Clan can supply values for those options. The router should validate them and generate the resulting configuration and dashboard inventory.

A fleet host can contribute a typed reservation and DNS record, tied to an explicit LAN. Cameras, APs, and other appliances should be expressible through the same reservation model without becoming Clan-managed machines. I’d use role membership for coordination and defer experimental exports until a concrete cross-instance use case needs them, such as a separate monitoring service consuming router endpoints.

### Q2. Shape [satisfied]

| Shape | Coupling and maintenance | Glue, portability, and testing |
|---|---|---|
| **1. First-party `clan.service`** | Highest public compatibility burden. The router maintainer owns the service schema and tracks Clan changes. | Best discovery and least setup for Clan users if the service covers their needs. Core VM tests can run without Clan, with additional tests for service evaluation and role wiring. Little direct benefit to standalone users. |
| **2. Optional adapter** | Contains Clan-specific compatibility work. A consumer-owned adapter avoids a second upstream release commitment while the interface settles. | Can centralize most reusable mapping. Test the router in plain NixOS VMs and check that the adapter maps a small Clan inventory to the expected router options. |
| **3. Consumer mapping plus upstream primitives** | Lowest upstream maintenance cost. The homelab still owns its fleet policy and mapping. | Generic HA and standby options benefit every consumer and are directly VM-testable. Each Clan consumer still has to wire up inventory and credentials. |
| **4. Router inventory feeds Clan** | Keeps Clan out of router internals but asks the fleet owner to adopt the router’s inventory schema as the shared source. | Gives non-Clan users a reusable network inventory. Clan lifecycle metadata and role mapping still need a home. Good for a network-first deployment, with a larger migration for this homelab. |

I’d start with **3**, evolve toward **2**, and consider **1** after someone outside the homelab demonstrates demand for a maintained service. Shape **4** makes sense when the operator already treats network inventory as authoritative for the fleet.

### Q3. Advisability [satisfied-conditional: validate the HA interface and consolidate the homelab’s inventory before publishing a maintained adapter]

Do the generic work now. Extract the HA pairing and standby behavior that can be expressed as plain NixOS options, then exercise a two-router VM setup through promotion and recovery. Move the remaining Kea reservations and DDNS inputs out of the predecessor repo so the homelab has one declared source for those records. Keep the router’s dashboard inventory derived from effective configuration.

Then build a thin adapter in the homelab and see what it actually removes from the 987-line aspect. The test is whether a clean inventory can express both a standalone router and an HA pair without importing site-specific policy. A second consumer is unnecessary for that experiment. I’d look for a second deployment before making a public Clan compatibility commitment, because it can show which adapter assumptions are specific to the first homelab.

### Q4. Community [satisfied]

Clan support would make the flake more attractive to operators who already use Clan for machine lifecycle and secrets. Its effect on broader adoption is unverified. The supplied star counts show a visibility gap, but they don’t tell us why people have or haven’t tried the project. The single known deployment leaves prospective users with little evidence about setup on a different network.

My top three changes, in order:

1. **Publish a copyable standalone router example.** Take a user from a two-interface topology to working routing, DHCP, and DNS. Show the exact inputs they need to change and the resulting configuration.
2. **Publish runnable NixOS VM tests for behavior users depend on.** Cover basic routing and firewall isolation, reservation and DNS generation, and HA promotion and recovery.
3. **Document the supported configuration surface and upgrade path.** Identify the options users should build on, which features are experimental, and how to migrate across breaking changes.

I’d prioritize all three over a rename or a first-party Clan service.

</details>

<details>
<summary>Gemini (agy)</summary>

### Perspective & Core Thesis

As Gemini in this roundtable, my position is grounded in systems modularity and ecosystem dynamics: **`nix-router-optimized` should not integrate directly with Clan today.** 

Prematurely coupling an infrastructure-tier network framework (591 commits, 0 stars, 1 maintainer) to an evolving multi-host framework (Clan-core 26.05 with experimental exports) adds architectural drag without expanding the user base. The 987-line consumer adapter in `nix-clan-homelab` is a symptom of missing multi-host abstractions in upstream router modules—not a mandate to bind the core router repository to Clan.

---

### Q1. Fit: Multi-Machine vs. Single-Host Concerns
**`[satisfied]`**

The boundary between fleet-level coordination and machine-local router execution is technically clean:

#### 1. Concerns that genuinely span machines (Clan roles, instances, and exports)
* **Fleet Addressing & Static Identity:** MAC-to-IP bindings for Kea DHCP static reservations and hostname-to-IP A/AAAA/PTR records for Technitium DNS. Fleet hosts (`lan-member` role) exporting network interfaces and MAC addresses to the router instance map naturally to Clan’s export paradigm.
* **High Availability & Redundancy Clustering:** Cross-router coordination between primary and backup nodes: VRRP virtual router IDs (VRID), VIP assignments, relative priority tiers, keepalived authentication tokens, and Kea DHCP active-standby replication/sync endpoints.
* **Shared Cross-Node Telemetry:** Prometheus scrape targets, distributed alerting hooks, and remote syslog egress.

#### 2. Concerns that must remain single-host NixOS options
* **Physical & L2 Interface Topologies:** Predictable interface names (`enp3s0`), PCIe bus mappings, VLAN trunk tagging, link-speed/offloading tunables (ethtool, GRO, TSO), and switch ASIC configurations. These depend strictly on the physical node hardware (e.g., bare-metal EliteDesk vs. Proxmox virtio NICs).
* **Local Kernel & Packet Path Policies:** NAT64/CLAT translation state, nftables base chain priorities, egress queueing disciplines (CAKE/fq_codel), sysctl network stack hardening, and CPU affinity for interrupt handling.
* **Secrets Realization & Local Daemon Runtime:** The router’s choice of plain `*File` options must remain agnostic of the secret delivery engine (agenix, sops-nix, or Clan vars). File path bindings and systemd service sandboxing are strictly node-local.

---

### Q2. Shape: Evaluation of Shapes 1–4
**`[satisfied]`**

| Criterion | Shape 1: In-Repo `clan.service` | Shape 2: Optional Adapter (`contrib/` or sub-flake) | Shape 3: Upstream Primitives + Consumer Glue (Status Quo Refined) | Shape 4: Router Inventory as Master Authority |
| :--- | :--- | :--- | :--- | :--- |
| **Coupling to Clan** | **Severe:** Ties router CI and module eval to Clan’s schema and experimental exports. | **Low:** Isolated to a subdirectory or satellite flake; core router remains untainted. | **Zero:** Core router remains completely decoupled from Clan. | **Inverted:** Forces Clan to consume a non-standard schema; brittle bidirectional mapping. |
| **Benefit to Non-Clan Users** | **Zero:** Clutters flake outputs; imposes cognitive overhead on standard NixOS users. | **None:** Irrelevant to non-Clan deployments. | **High:** Generic multi-router HA/standby options upstream benefit any NixOS cluster (Colmena, deploy-rs). | **Low:** Requires adopting router's custom inventory format. |
| **Consumer Glue Reduction** | **High:** Collapses 987-line role into a Clan service invocation. | **High:** Offloads adapter logic into the shared adapter. | **Moderate-High:** Shrinks glue significantly by upstreaming generic HA logic. | **Moderate:** Replaces glue with inventory translation passes. |
| **Testability (Pure VM Tests)** | **Poor:** Testing the Clan service requires pulling Clan inputs into tests. | **Good:** Core tested via standard `nixosTest`; adapter tested separately. | **Best:** Multi-node VRRP/Kea HA easily validated with standard pure `nixosTest` nodes. | **Complex:** Requires round-trip validation between inventories. |
| **1-Maintainer Maintenance** | **High Burden:** Upstream API shifts in Clan force emergency fixes in the router repo. | **Medium:** Can bit-rot gracefully without breaking core router releases. | **Lowest:** Maintainer refactors only general features; site-specific glue stays where it is used. | **High:** Ongoing schema synchronization friction. |

**Verdict:** **Shape 3 is the correct architectural path today.** It separates generic multi-node router logic from the consumer's deployment tool. If Clan adoption surges later, **Shape 2** serves as the only viable bridge. Shape 1 is an anti-pattern for an infrastructure flake.

---

### Q3. Advisability: Roadmap & Timing
**`[satisfied-conditional: Upstream HA primitives first and await Clan exports stabilization]`**

Integrating with Clan upstream should **not be done now**. 

For a single-maintainer project, building an upstream Clan module for an $N=1$ consumer (where the maintainer already owns both repositories) constitutes premature abstraction. It expends finite maintenance bandwidth tracking Clan internals instead of hardening router capabilities.

#### What must happen first:
1. **Upstream Generic Multi-Router Primitives:** The 987-line `router-role` in `nix-clan-homelab` contains generic router logic mixed with site glue. Upstream should introduce native NixOS options for multi-node setups—such as typed VRRP peer definitions, failover safety guards, and Kea HA replication—as pure `services.router-ha.*` options testable via standard multi-node `nixosTest`.
2. **Sever Consumer Legacy Ties:** The consumer must stop sourcing DHCP/DNS definitions from its predecessor repository's `lib/hosts.nix` and fully adopt a single host authority.
3. **Stabilization of Clan's Export Mechanism:** Clan-core's `exports` feature is explicitly experimental. Building cross-node address publishing against an unstable API creates an unnecessary maintenance sink.
4. **Validation via an External Consumer:** A second, independent user must express a concrete requirement for Clan-native integration before committing to maintaining that interface.

---

### Q4. Community Appeal & Adoption Bottlenecks
**`[satisfied]`**

**Clan integration will not make `nix-router-optimized` noticeably more attractive to the broader NixOS community.**

Clan itself is a specialized, emerging tool within the ecosystem (182 GitHub mirror stars vs. 417 stars for `chayleaf/nixos-router`). The vast majority of NixOS networking practitioners manage routers via standalone flakes, Colmena, deploy-rs, or standard `nixos-rebuild`. Tying the router’s identity or documentation to Clan risks alienating non-Clan users by making the project appear dependent on an idiosyncratic orchestration layer.

The project’s lack of adoption (0 stars) is driven by discoverability, ease of evaluation, and perceived operational risk—not the absence of a Clan module.

#### The 3 Changes Most Likely to Attract Users (in order of impact):

1. **Self-Contained "Appliance" Quickstarts with Interactive VM Demos**
   * *Action:* Provide three turnkey, copy-pasteable flake configurations: (a) a single-node dual-NIC home gateway, (b) a router-on-a-stick with VLAN trunking, and (c) a 2-node active/standby VRRP pair.
   * *Impact:* Package them with an interactive `nix run .#demo-vm` script that launches a multi-node QEMU network. Users can test firewalling and Kea DHCP leases locally without touching physical hardware, dramatically lowering the evaluation barrier.

2. **Modular Decoupling of the 55 Modules**
   * *Action:* Ensure users can adopt the framework incrementally. A user should be able to consume *just* the typed zone/nftables abstraction, or *just* the Kea/Technitium integration, without committing to the full opinionated topology model or dashboard.
   * *Impact:* Enables integration into existing, established NixOS server fleets that already have their own interface and host management.

3. **Public Technical Comparisons and Visual Artifacts**
   * *Action:* Publish a comprehensive technical comparison ("Why `nix-router-optimized` vs. `chayleaf/nixos-router` vs. raw NixOS networking"), highlighting evaluation-time assertion safety and nftables generation. Feature rich screenshots and live demos of the generated topology dashboard on the documentation site, followed by an announcement on NixOS Discourse.
   * *Impact:* Solves the zero-discoverability problem by directly demonstrating tangible value to network engineers already looking for robust NixOS routing solutions.

</details>

<details>
<summary>Claude (claude -p)</summary>

## Claude's position

**Short version:** Don't put Clan into nix-router-optimized now. Move the generic HA and standby logic out of the 987-line `router-role` and into plain upstream NixOS options. Then, later and only if it turns out to be cheap, ship an optional Clan adapter (shape 2, eventually written as a `clan.service`). Clan won't decide adoption. Zero stars and a single consumer are the real problem.

---

### Q1. Fit — `[satisfied]`

**Concerns that really span machines** (a good fit for Clan roles, instances and exports):
- **VRRP pairing.** Two or more machines share a VIP, a priority ordering, a preempt delay and an auth secret. This is exactly what Clan roles are for: a `router` role with `primary`/`backup` settings, where each member can see its peers. Kea HA peering has the same shape: each peer needs the other's URL and role.
- **DHCP reservations and DNS records for fleet hosts.** The facts belong to the hosts (MAC, wanted IP, hostname), but the routers consume them. A `lan-member` role, or exports, would let a host declare "give me 10.0.20.15" next to its own definition. This is the strongest argument for Clan, but it depends on exports, which are experimental.
- **Shared credentials** (VRRP auth, Kea HA, DDNS TSIG keys). Clan vars with sharing across machines fit well. But the router already takes `*File` options, so the router flake doesn't need to know about Clan for this.
- **Monitoring targets.** The router's exporters become scrape targets for whatever runs Prometheus. That's a generic exports use case and nothing router-specific.

**Concerns that must stay single-host NixOS options:** interface and zone topology, nftables generation, the internals of Kea and Technitium, CLAT/NAT64, hardening, the dashboard, and most importantly the **evaluation-time assertions**. The typed topology model is the product. If it's split across Clan settings, users lose the single place where invariants are checked. Standby safety (what a backup does with WAN, DHCP and DNS when it isn't master) is mostly local behaviour driven by a "role" input. It belongs upstream as an option, not in Clan.

### Q2. Shape — `[satisfied]`

| | Coupling to Clan | Benefit to non-Clan users | Cuts consumer glue | VM tests without Clan | One-maintainer cost |
|---|---|---|---|---|---|
| 1. Native `clan.service` | High: tracks the clan.service API and experimental exports | None, and maybe negative (more surface, confusing docs) | High | Weak: the core can still be tested, but the service needs Clan's test harness | High |
| 2. Optional adapter (`contrib/clan/` or separate flake) | Isolated | Neutral | Medium–high | Core tests are unaffected | Medium, and can be dropped if Clan churns |
| 3. Keep in consumer, move generics upstream | None | **High**: VRRP pairing and standby options help everyone | Medium (987 → maybe ~300 lines, unverified estimate) | Full | Low |
| 4. Router inventory as source of truth for Clan | Low in code, but it pushes the router into fleet management | Low | Unclear | Full | Medium, and it inverts the design (see below) |

Shape 4 is the wrong direction. The router should not own the fleet. `homelab.hosts` already holds cameras, APs, SSH targets and roles, which aren't router concerns. Discussions 11 and 12 made the repo-native inventory the authority *for the router's view*. Turning it into the authority for the whole fleet would be scope creep.

Shapes 3 and 2 work best in sequence. Shape 3 creates the clean, generic option surface (for example `services.router-ha.peers`, `role`, `priority`, `standby.*`, and a reservations list with a stable schema). Once that surface exists, a shape 2 adapter is a thin translation, probably under 200 lines. It could legitimately be written as a `clan.service` living in `contrib/`, exported as `clan.modules."@…/router"`, with no dependency in the core flake. That gives you shape 1's user experience with shape 2's coupling.

### Q3. Advisability — `[satisfied-conditional: generic HA/standby options land upstream and the consumer stops reading the predecessor repo's `lib/hosts.nix`]`

**Later, not now.** Prerequisites, in order:
1. **Upstream the generic parts of `router-role`.** That means VRRP peer pairing, credential wiring for the master, Kea HA peer config and standby behaviour, all as plain options covered by VM tests (two-router failover in `nixosTests`). If that code can't be written generically, a Clan service built on top of it will just bake in the consumer's quirks.
2. **Remove the dependency on the predecessor repo.** Reservations and DDNS should come from one typed source in the consumer. Until then, every integration shape would be wrapping a temporary data path.
3. **A stable reservation/host input schema** that the router accepts as data, for example `services.router-dhcp.reservations = [ { mac; ip; hostname; zone; } ]`. Any adapter, Clan or not, writes to this.
4. **Wait for Clan exports to stabilise**, or design the adapter to use only roles and settings for now. Building the main value proposition on an experimental feature with one maintainer is a poor trade.
5. **A second consumer is nice-to-have, not required.** For a Clan adapter specifically, it would be the best signal: if a Clan user asks for it, build it.

If these hold, a `contrib/clan` service is a reasonable weekend-sized addition. If they don't, it adds a second translation layer next to the existing one.

### Q4. Community — `[satisfied]`

Clan integration would make the flake *slightly* more attractive to a small audience: Clan users who also want a NixOS router. clan-core's 182 GitHub stars (per the leader's figures) show that audience is small, though the mirror probably undercounts because development happens on git.clan.lol. That's a marketing footnote, not a growth engine. For comparison, chayleaf/nixos-router has 417 stars and no fleet framework, which suggests router users are mainly judging the router itself.

Adoption today is held back by things unrelated to Clan:
- **0 stars, 1 consumer, 591 commits from one person.** To an outsider that reads as "personal config published as a framework" and a bus-factor risk.
- **No visible way to get started.** About 55 modules is intimidating without a 30-line example that boots.
- **No visible stability promise.** It's unclear which options are stable and whether there are tagged releases or a changelog.
- **Naming.** "optimized" says nothing. The real differentiator is the typed topology with derived firewall, DHCP and DNS plus eval-time assertions, and the name doesn't convey it. (This is a soft point and my opinion.)

**The three changes most likely to attract users, in order:**
1. **A minimal, copy-pasteable example with a VM test you can run with one command.** For example, `examples/minimal` (one WAN, one LAN, one guest zone) and `examples/ha-pair`, each with a `nixosTests` run that people can try via `nix run .#checks...`. A failover demo that runs in CI is the strongest evidence a router framework can offer.
2. **Tagged releases with a stable-options policy and a changelog.** Mark the core topology, firewall and DHCP options as stable and everything else as experimental. People won't put a framework on their network edge if it might break on the next `flake update`.
3. **Explain the differentiator and put it where people look.** Write a comparison page against nixos-router and plain NixOS networking that shows "declare the topology once, get nftables, Kea, DNS and dashboard, with eval errors when they disagree." Post it on NixOS Discourse with the HA demo. Consider making the name say what the project does.

A Clan adapter would come fourth, after these, and it's most compelling once the HA pair example exists, because the HA pair is the one place where Clan's multi-machine roles clearly beat plain options.

**Bottom line:** Make the router great as plain NixOS first: move the generic HA logic upstream, add examples, tests and releases. Clan can come later as a thin optional adapter, built when someone asks for it, not as a bet on adoption.

</details>

<details>
<summary>Copilot (copilot -p)</summary>

# Claude's position

**Q1. Fit.** VRRP pairing (primary/backup role with priority/preempt as settings), credential distribution to the master (clan vars → router's `*File` options), and monitoring/alerting targets genuinely span machines and map cleanly onto Clan roles/instances/exports — these are inherently "who is my peer, what do they need from me" problems that Clan's model exists to solve. DHCP reservations and DNS records for fleet hosts are murkier: they're per-host *data* (address, hostname, MAC) rather than per-host *role behavior*. That data could be carried as exports from `lan-member` machines, but the actual reservation/record generation is still single-host logic that belongs in the router's own typed inventory, which this project already decided (discussions 11/12) is the single authority. Firewall zones, nftables, CLAT/NAT64, hardening — single-host, no fit, should never touch Clan.

**Q2. Shape.** 
- Shape 1 (native `clan.service`) maximizes benefit to Clan users but couples the router flake's API surface to Clan's experimental `exports` mechanism and to clan-core's own churn (26.05, pre-1.0 conventions). It also forces non-Clan users (the only kind that currently exist outside this one maintainer) to read Clan concepts to understand even the VRRP docs. Worst ratio of risk to current payoff.
- Shape 2 (optional adapter, `contrib/clan/` or separate flake) isolates the coupling, keeps the core testable in plain VM tests with zero Clan dependency, and gives Clan users a real reduction in glue without taxing everyone else. This is the correct shape *if and when* integration happens, because it lets the adapter evolve/break independently of the core's stability guarantees.
- Shape 3 (status quo, consumer owns the 987-line `router-role`) is actually fine as an interim step, and arguably necessary groundwork: it's where you discover which parts of that glue are generic (VRRP pairing, standby safety, "who is master" logic) versus homelab-specific (cameras, APs). Promoting the generic parts to plain NixOS options in the router flake is valuable with or without Clan ever entering the picture.
- Shape 4 (router inventory as upstream source for Clan) inverts the dependency in a way that's architecturally interesting but currently unrealistic — it asks Clan's machine-lifecycle tooling to subscribe to a single-maintainer flake's data model. Not worth pursuing until the router inventory is far more battle-tested and has independent adoption.

**Q3. Advisability.** Not now. Do shape 3 first: extract the generic VRRP-pairing and standby-safety logic from `router-role` into plain NixOS options in nix-router-optimized (this benefits every consumer, Clan or not, and is low-risk since it's just moving option definitions, not adopting new concepts). Stop the consumer reading the predecessor repo's `lib/hosts.nix` for Kea/DDNS — that's an existing inconsistency independent of Clan and should be resolved regardless. Only after both of those, and ideally after a second consumer exists (even a toy/example one), does writing a Shape 2 adapter make sense, because at that point you'd actually know what's generic versus homelab-specific instead of guessing from n=1. Integrating now, with one maintainer, one consumer, and Clan's exports marked experimental, would mean maintaining a moving target's API against a single data point — classic premature abstraction.

**Q4. Community.** Clan integration would help a specific, small slice of the NixOS community (people already committed to Clan who want a router) but is not close to the top of what's limiting adoption. Zero stars, single consumer, and no public examples mean most potential users never get far enough to care whether it has Clan hooks — they can't tell if the project is maintained, evaluate the typed-topology claim, or even find a quickstart that produces a running router outside its one bespoke homelab context. The three changes most likely to attract users, in order:

1. **A standalone example/quickstart repo** (or `examples/` in-tree) showing a minimal single-router and a VRRP-pair config from scratch, with no dependency on clan-core or the private homelab repo — this is the single biggest blocker: nobody can evaluate a framework they can't run.
2. **VM tests visible in CI with a results badge**, demonstrating the nftables/Kea/Technitium derivation claim actually holds under evaluation-time assertions — this substitutes for the trust signal that stars/users would normally provide.
3. **Documentation of the typed topology model as the headline feature**, positioned against the more popular chayleaf/nixos-router (417 stars) — explaining concretely what "derive nftables/DHCP/DNS from one topology" buys you that writing each module by hand doesn't.

Clan support, if it comes, should be change #4 or later, built as an opt-in adapter once there's already a visible, documented, runnable project that non-Clan users can evaluate on its own terms.

- Q1: [satisfied-conditional: VRRP/credentials/monitoring fit Clan roles; DHCP/DNS reservation *data* can be exported but *generation logic* stays in router's own inventory per discussions 11/12]
- Q2: [satisfied-conditional: Shape 2 is correct *if* integration proceeds; Shape 3 is correct as immediate next step regardless]
- Q3: [satisfied-conditional: later — after generic HA/standby options are upstreamed, predecessor-repo dependency is removed, and ideally a second consumer exists]
- Q4: [satisfied-conditional: Clan integration is not among the top 3 levers; examples, VM-test visibility, and topology-model documentation outrank it]

</details>

<details>
<summary>DeepSeek (API)</summary>

## Q1. Fit — `[satisfied-conditional: the router's own inventory stays authoritative for DHCP/DNS; Clan only supplies machine identity and cross-machine facts]`

Genuinely cross-machine, and therefore good fits for Clan roles/instances/exports:

- **VRRP pairing** (`router-ha`): primary/backup membership, priority, preempt delay, and "which credentials the master needs" are inherently multi-machine. This is the strongest candidate.
- **DHCP reservations and DNS records for fleet hosts**: the *data* is cross-machine (host X wants a reservation), but the *authority* should remain the router's typed inventory (per earlier decisions 11/12). Clan exports could feed it, not replace it.
- **Monitoring/alerting targets and dashboard aggregation**: naturally fleet-scoped.
- **WAN identity / CLAT / NAT64 role assignment**: per-router, but the pairing of which router holds which WAN is fleet-level.

Must stay single-host NixOS options:

- nftables ruleset generation, zone definitions, interface typing, hardening, Kea/Technitium daemon config, CLAT mechanics. These are evaluated per machine and benefit from evaluation-time assertions that Clan's inventory layer doesn't model.

The clean split: **topology and host facts are fleet-level; derivation and enforcement are single-host.** Clan should carry identity and membership; the router should carry semantics.

## Q2. Shape — `[satisfied-conditional: shape 2 now, shape 1 only after a second consumer exists]`

- **Shape 1 (export `clan.service`)**: Best end-user ergonomics, worst coupling. Clan's service API is young (exports are explicitly experimental in 26.05), and a 591-commit, one-maintainer flake tracking a fast-moving framework is a maintenance tax with no current payoff (zero Clan consumers besides one). Also drags Clan into the router's test path unless carefully isolated.
- **Shape 2 (optional adapter, `contrib/clan/` or separate flake)**: Best ratio. Keeps the router Clan-agnostic (benefits non-Clan users, preserves VM tests without Clan), localizes churn to one directory, and lets the consumer's 987-line `router-role` shrink incrementally. Recommended.
- **Shape 3 (do nothing; slim consumer glue by upstreaming generic options)**: Cheapest, and honestly defensible today. Upstreaming generic VRRP-pairing and standby-safety options as plain NixOS options helps *all* users, Clan or not. But it leaves the consumer carrying fleet-mapping logic that will drift.
- **Shape 4 (router inventory as source for Clan)**: Inverts the dependency and makes the router responsible for Clan's model. Rejected — it makes a router framework own fleet lifecycle, which is Clan's job, and contradicts decisions 11/12 about authority.

On the four axes: coupling — 2 < 3 < 1 < 4. Non-Clan benefit — 3 ≈ 2 > 1 > 4. Glue reduction — 1 > 2 > 3 > 4. Testability without Clan — 2 ≈ 3 > 1 > 4. One-maintainer maintenance — 3 < 2 < 1 < 4.

## Q3. Advisability — `[needs more evidence: a second consumer and a stabilized Clan service/exports API]`

**Later, not now, and probably not "never."** Preconditions:

1. **Generic HA/standby options upstreamed as plain NixOS options** (shape 3 work) — this is valuable regardless of Clan and de-risks shape 2.
2. **The consumer stops reading the predecessor repo's `lib/hosts.nix`** for Kea reservations and DDNS. Until that's migrated into `homelab.hosts` (or the router inventory), any Clan adapter is mapping a half-migrated model and will be rewritten.
3. **A second consumer** — ideally one that is *not* the maintainer's homelab. With one consumer, "integration" is really "extracting the consumer's private glue," which is fine but should be framed as such.
4. **Clan's service/exports API stabilizes** past experimental, or the adapter is written to tolerate churn (shape 2's isolation helps here).

Doing shape 1 now would be premature: it couples a zero-star, single-consumer flake to an experimental API of a 182-star framework, for an audience of one.

## Q4. Community — `[satisfied-conditional: Clan integration is a marginal adoption lever; the binding constraints are elsewhere]`

Clan integration would make the flake *somewhat* more discoverable to Clan users (a real, growing niche), and a well-scoped `clan.modules."@author/nix-router-optimized"` export is a legitimate distribution channel. But it is unlikely to be the thing that moves adoption. The comparison point is telling: `chayleaf/nixos-router` has 417 stars; this flake has 0 with 591 commits and a docs site. That gap is not explained by Clan compatibility — it's explained by discoverability, examples, and trust signals.

Three changes most likely to attract users, in order:

1. **A copy-pasteable, tested example**: a minimal two-router VRRP + Kea + Technitium config with a VM test that boots it and asserts failover. This is the single highest-leverage artifact; it demonstrates the typed-topology pitch concretely and gives people something to run.
2. **Visible stability and test coverage**: CI running VM tests, a versioning/changelog story, and a clear "what's supported" matrix. Zero stars plus one maintainer reads as risk; tests and releases reduce that.
3. **Documentation that leads with the differentiator**: the typed topology → derived nftables/Kea/DNS/dashboard with evaluation-time assertions, shown side-by-side against hand-written config. Clan integration belongs here as a *section*, not the headline.

Clan integration is a reasonable fourth item and a good fit for shape 2 once the preconditions in Q3 hold — but it is a distribution detail, not the adoption bottleneck.

</details>

<details>
<summary>OpenCode enrichment seat (big-pickle)</summary>

## Q1. Fit `[satisfied-conditional: clear source-of-truth boundary between fleet intent and router-derived artifacts]`

**Good Clan fits (cross-machine concerns):**
- **VRRP/HA pair**: primary/backup roles, priority/preempt/VIP settings, and master-only credentials. This naturally spans two machines and matches Clan roles/instances.
- **Fleet DHCP reservations & DNS records**: `lan-member`/host roles can publish hostname, MAC, address intent; router role consumes them to generate Kea/Technitium config. Fits Clan exports/instance wiring.
- **Monitoring/alerting targets**: router exports endpoints/status targets; a monitoring service consumes them. Aligns with Clan’s existing service/export pattern.
- **Credential assignment metadata**: which node needs which secret (not secret values) can map to Clan vars/instances; actual secrets should remain plain `*File` options.

**Should stay single-host NixOS options:**
- Typed topology internals: interfaces, subnets, zones, nftables derivation, NAT64/CLAT, hardening, daemon tuning, dashboard rendering.
- Router-local assertions and generated read-only inventory artifacts. These are derived from one router’s config, not fleet authority.

**Boundary:** Clan inventory should express fleet intent; nix-router-optimized should derive router artifacts. Inverse authority (shape 4) risks conflicting sources of truth.

## Q2. Shape `[satisfied]`

| Shape | Clan coupling | Non-Clan benefit | Consumer glue reduction | Testability (no Clan) | Maintainer burden |
|---|---|---|---|---|---|
| **1. Export `clan.service` from router flake** | High; tracks Clan service/exports API (exports noted experimental) | Low/indirect | High for Clan users | Lower; needs Clan harness or dual test paths | High for one maintainer |
| **2. Agnostic core + optional Clan adapter** | Isolated to adapter | High; core unchanged | Medium-high for Clan users | High for core; adapter tested separately | Moderate if adapter is separate/consumer-owned |
| **3. Consumer mapping; upstream generic NixOS primitives** | None | High; helps any NixOS router user | Moderate; removes generic VRRP/standby/credential-shape boilerplate | Highest; plain NixOS VM tests | Lowest, aligned with current design |
| **4. Router inventory as shared source for router+Clan** | Inverted/conceptual coupling | Unclear | Possible, but creates authority conflicts | Complicated dual-authority model | High; conflicts with prior single-authority decision |

**Assessment:** Shape 3 now, shape 2 later if demand appears. Shape 1 is premature for a single maintainer. Shape 4 is architecturally risky.

## Q3. Advisability `[satisfied-conditional: generic HA primitives upstream, predecessor-repo decoupling, and evidence of a second consumer or stable Clan API demand]`

**Not now** for a built-in Clan inventory integration. **Later**, as an optional adapter, if prerequisites are met.

**Do now:**
- Extract generic, Clan-agnostic pieces from the 987-line `router-role`: VRRP pair modeling, standby-safe behavior, master/backup credential requirements, Kea HA wiring hooks. These should be plain NixOS options with VM tests.
- Decouple the consumer from the predecessor repo’s `lib/hosts.nix`; make the current inventory path authoritative.

**Before Clan integration:**
- A second real consumer or explicit Clan-user demand (unverified today).
- Evidence Clan service/exports interfaces used are stable enough; exports are experimental in the provided context.
- A narrow adapter prototype that does not pull Clan into core tests/deps.

**Not at all:** making Clan a required dependency or making router-derived inventory the fleet source of truth.

## Q4. Community `[satisfied]`

Clan integration would make the flake **slightly more attractive to existing Clan users**, but it is unlikely to drive broad NixOS adoption. Clan-core’s 182 stars indicate a niche ecosystem (star counts are a coarse signal, unverified as proxy for active users). The bigger blockers are maturity signals: 0 stars, single known consumer, and no obvious external proof.

**Top 3 changes most likely to attract users, in order:**
1. **Runnable, CI-tested examples/VM tests** - publish minimal lone-router and VRRP-pair reference configs with NixOS VM tests. Users adopt what they can boot and verify.
2. **Adoption-focused docs and positioning** - quickstart, option/reference docs, migration guide, and a clear “when to use this vs plain NixOS/chayleaf/nixos-router” comparison (feature/parity claims unverified).
3. **Stability and release discipline** - versioned releases/changelog, explicit compatibility policy, and stable module interfaces so users aren’t tracking a single-consumer moving target.

Clan integration ranks after these; it’s a distribution channel, not the primary adoption driver.

</details>

### Narrowed follow-up

<details>
<summary>Narrowed follow-up prompt</summary>

ROUNDTABLE follow-up (narrowed): nix-router-optimized and Clan

You answered round 1. All six voices converged: do not integrate Clan now; first move generic HA/standby logic from the consumer's 987-line `router-role` into plain upstream NixOS options with VM tests, and remove the consumer's dependency on the predecessor repo; later, an optional adapter (shape 2), with a native `clan.service` only on demand; reject shape 4 (Codex: acceptable only where network inventory is already the fleet authority). Clan integration is not a top-3 adoption lever; your top 3 were runnable examples with VM tests, stability/releases, and docs that lead with the typed-topology differentiator.

The discussion leader's round 1 context omitted facts that bear on your answers. Verified 2026-11-25:

F1. The flake already has `examples/` (`router-single-basic.nix`, `router-ha-pair-example.nix`, `basic-router.md`, plus DNS-zone, BGP/Proxmox lab, dashboard remote access, NDP proxy) and over 30 tests under `tests/` wired into `checks` (including `router-ha-lab`, `router-ha-ownership`, `router-ha-vrrp-auth`, `router-ha-boundaries`, `router-assertions`, `doc-examples`, `interface-firewall-invariants`, dashboard inventory). There are git tags up to `v0.10.0`, but zero GitHub Releases, no changelog file at top level, no repository topics, and the README does not point to a quickstart or the examples near the top (it links RECIPES and comparison docs).

F2. Upstream `services.router-ha` already has: role, virtualIp, vrrpId, password file, priority, preemptDelay, singleActiveUnits, WAN takeover (cloned MAC, shared DHCP identity, health checks with failure/grace/retry), transition scripts, Kea HA peer address. What remains in the consumer's `router-role` is mainly: mapping `homelab.hosts` to these options; a manual-failover `specialisation` for a standby before VRRP; standby guards (WAN down, no Kea/UPnP/DDNS); an abort fence; MASTER-only units without an upstream ownership option (Pangolin/gerbil); a Technitium zone-HA owner driven by a role file; NIC/SFP alert rules; credential gating by mode.

F3. Discussion 11's "repo-native host inventory is the single authority" refers to the consumer fleet repo's host list (then unified's `lib/hosts.nix`, which also holds SSH metadata, ingress and DDNS labels), not to an inventory inside nix-router-optimized. The router flake's dashboard "inventory" is derived read-only from router options (`router-dhcp` staticLeases, `router-kea` reservations, Technitium). Some round 1 answers read decision 11 as making the router flake the authority.

F4. nix-router-optimized already ships `services.router-security-hardened` (kernel/network sysctls, module blacklist); the consumer does not enable it because it forces strict `rp_filter` while the consumer needs loose.

Answer only these, under 500 words, marking each with `[satisfied]`, `[satisfied-conditional: X]` or `[needs more evidence: X]`:

N1. Given F1, restate your top 3 adoption changes. Is the gap building examples/tests, or making the existing ones visible and trustworthy (releases, changelog, README quickstart, CI badge, topics, Discourse post)?

N2. Given F2, which consumer-side pieces should move upstream as generic options, and which are site policy that should stay in the consumer? One sentence each is enough.

N3. Round 1 split on whether a second consumer is required. Codex and Claude: not needed to prototype an adapter inside the consumer, needed before publishing a maintained upstream adapter. Gemini and DeepSeek: required first. State your rule.

N4. Given F3, where should DHCP reservations and DNS records for fleet hosts be authored, and what should the router flake accept as input?

</details>

<details>
<summary>Codex</summary>

**N1 [satisfied]** The adoption gap is discoverability and release confidence. My top three changes are:

1. Lead the README with the typed-topology differentiator and a runnable quickstart linked to the existing single-router and HA examples.
2. Publish GitHub Releases from the tags, maintain a changelog, and put a CI badge near the quickstart that reflects the status of the existing flake checks.
3. Add repository topics and publish a NixOS Discourse walkthrough that shows how a typed topology becomes a working router and links to the examples and VM checks.

**N2 [satisfied]** Upstream the generic standby activation controls, including WAN and service suppression, a failover abort guard, and any role-ownership hooks that `singleActiveUnits` and the existing transition scripts cannot express. Keep the manual `specialisation`, `homelab.hosts` mapping, Pangolin and Technitium ownership wiring, NIC/SFP alert rules, and credential gating in the consumer.

**N3 [satisfied]** Prototype the optional Clan adapter inside the existing consumer once it can use the plain upstream options. Publish and maintain it upstream only after a second independent consumer validates the same adapter interface against its own inventory and deployment workflow.

**N4 [satisfied]** Author fleet-host DHCP reservations and DNS records in the consumer fleet’s authoritative inventory, or in consumer-owned declarations keyed to it. Have the consumer project that data into the router flake’s typed DHCP reservation and DNS record or zone options. The dashboard can continue to derive its read-only view from the resulting router configuration.

</details>

<details>
<summary>Gemini (agy)</summary>

### N1. Top 3 Adoption Changes `[satisfied]`

The gap is **making existing infrastructure visible and trustworthy**, not authoring new examples or tests.

1. **Trust Signals & Release Hygiene**: Publish formal GitHub Releases corresponding to tags, add a root `CHANGELOG.md`, and display a CI badge reflecting the 30+ passing tests.
2. **README Quickstart**: Put a 5-minute quickstart at the top of the README linking directly to `examples/` and test recipes, leading with typed-topology correctness guarantees.
3. **Ecosystem Reach & Unblocking Adoption**: Add repository topics, announce on NixOS Discourse, and make `services.router-security-hardened.rpFilter` configurable (`strict` vs. `loose` per F4) so consumers can adopt upstream hardening without manual overrides.

---

### N2. Upstream vs. Site Policy `[satisfied]`

* **Move upstream (generic options)**: Upstream should provide generic standby fencing/guards (suppressing specified systemd units and WAN links on standby), expand `singleActiveUnits` to accept arbitrary user-specified systemd units, and make `router-security-hardened.rpFilter` configurable.
* **Keep in consumer (site policy)**: Site policy must retain the transformation of consumer fleet inventory (`lib/hosts.nix`) into router options, custom third-party daemon coordination (Pangolin, Technitium zone-HA file sync), NIC/SFP alert rules, and mode-based credential gating.

---

### N3. Second Consumer Rule `[satisfied]`

**Rule**: Prototype and dogfood the Clan adapter out-of-tree inside the primary consumer repo (or an experimental flake output) first, but require an independent second consumer with distinct network requirements before promoting the adapter to a committed, maintained upstream contract.

---

### N4. Inventory Authority & Router Flake Contract `[satisfied]`

* **Authoring**: Host DHCP reservations and DNS records must be authored in the consumer fleet repository (e.g., `lib/hosts.nix`), which serves as the sole source of truth for machine identity, addressing, and roles.
* **Router Flake Input**: `nix-router-optimized` must remain inventory-agnostic, accepting plain typed submodules (e.g., `services.router-dhcp.staticLeases = [ { mac; ip; name; ... } ]`, Kea reservations, and static DNS record lists) that consumer code maps from fleet data.

</details>

<details>
<summary>Claude (claude -p)</summary>

**N1. Top 3 adoption changes** `[satisfied]`

Given F1, the gap is not missing examples or tests. They exist but are hard to see and hard to trust. My revised top 3:

1. **Make releases trustworthy.** Publish GitHub Releases for v0.10.0 onward, add a top-level CHANGELOG, and write a short stability/deprecation policy saying which options are stable and how renames are handled.
2. **Put the quickstart first in the README.** Show a copy-paste `router-single-basic.nix`, then link `router-ha-pair-example.nix` and say plainly that it is covered by `router-ha-lab`/`router-ha-ownership` in CI. Add a CI badge, and lead with the typed-topology differentiator before RECIPES and the comparison docs.
3. **Make the project discoverable.** Add repo topics (nixos, router, vrrp, kea, flake), post on Discourse with the HA-pair example, and list the project in nixos-wiki's router pages.

The remaining build work is the HA upstreaming in N2, which also strengthens #2.

**N2. Upstream vs. consumer** `[satisfied-conditional: each upstream option ships with a VM test extending router-ha-* checks]`

Move upstream as generic options:
- **Standby guards:** an option on `router-ha` that keeps WAN down and lists units that must not run on the standby (Kea, UPnP, DDNS).
- **MASTER-only units:** generalize `singleActiveUnits` into an ownership option for any unit, so Pangolin/gerbil become config, not code.
- **Abort fence:** a generic "refuse to promote if X" hook with a test.
- **Manual-failover specialisation:** an opt-in `router-ha.mode = "manual"` that generates the specialisation. Many users run a cold standby before VRRP.
- **Credential gating by mode:** a generic pattern that ties secrets to the active role.

Keep in the consumer as site policy:
- **Mapping `homelab.hosts` to options:** the consumer's inventory schema belongs to the consumer.
- **Technitium zone-HA owner via role file:** stays until a second user wants it. Upstream could expose a role-file path as a generic "current role" signal.
- **NIC/SFP alert rules:** thresholds and hardware are specific to the site.
- **`rp_filter`:** separately (F4), make `router-security-hardened` expose a configurable `rp_filter` (strict by default, loose allowed). That way the consumer can enable it instead of skipping the whole module.

**N3. Second-consumer rule** `[satisfied]`

My rule is the same as Codex's and Claude's in round 1. Prototyping an adapter inside the consumer needs no second consumer. Publishing it upstream as maintained needs one real external user, or at least a second fleet layout in a VM test that is not just a copy of this one. Generic HA options from N2 do not need a second consumer, because VM tests are their proof. The bar applies only to adapters that encode a particular inventory shape.

**N4. Where reservations and DNS records are authored** `[satisfied]`

Given F3, I was wrong in round 1 if I read decision 11 as making the router flake the authority. Fleet hosts' DHCP reservations and DNS records should be authored in the consumer fleet repo's host inventory (`lib/hosts.nix`), which is the single authority. The router flake should accept plain typed NixOS options as input: `router-kea` reservations, `router-dhcp` staticLeases and the DNS-zone record options. The consumer maps its inventory onto those options.

The router flake should not define or import a host-inventory schema. Its dashboard "inventory" stays a read-only view derived from those options. If an adapter (shape 2) appears later, it is just that mapping function, `hosts → router options`, living in the consumer or in an optional `lib/` helper.

</details>

<details>
<summary>Copilot (copilot -p)</summary>

N1. [satisfied] Top 3 unchanged, but re-weighted toward visibility: (1) Discoverability/trust — cut a GitHub Release at v0.10.0+ with a changelog, add topics and a CI badge, and move the README's first screen to a quickstart pointing at `examples/router-single-basic.nix` and `router-ha-pair-example.nix`. (2) Keep the VM-test discipline as the selling point — advertise `router-ha-lab`/`router-ha-ownership`/`router-ha-vrrp-auth` in the README/Discourse post as "this is tested," since that's already true and just unmarketed. (3) Remove the consumer's dependency on the predecessor repo (unchanged from round 1 — still the real blocking adoption lever, orthogonal to F1). Given F1, the gap is overwhelmingly visibility/trust, not content: examples and ~30 wired checks already exist. Building more examples now would be redundant effort; the fix is packaging what exists (release, changelog, quickstart-first README, topics) so a newcomer can find and trust it in under five minutes.

N2. [satisfied] Move upstream as generic options: the `homelab.hosts`→role mapping pattern (as a documented convention, not code), the manual-failover specialisation for pre-VRRP standby, the standby guard set (WAN-down / no-Kea / no-UPnP / no-DDNS) as a generic `router-ha` "standby inhibitors" option, and the abort fence as a generic safety primitive. Stay in consumer (site policy): MASTER-only Pangolin/gerbil ownership (app-specific, not router-generic), the Technitium zone-HA role-file owner (couples to a specific DNS deployment shape), NIC/SFP alert thresholds (hardware/site-specific), and credential gating by mode (secrets-management policy, not router logic).

N3. [needs more evidence: how "maintained upstream adapter" is scoped] Rule: a second consumer is not required to prototype an in-consumer adapter module (low cost, reversible, no public API commitment) — Codex/Claude's position. A second consumer *is* required before publishing it as a maintained upstream Clan adapter, because "maintained" implies an API contract, and one data point can't distinguish "this consumer's quirks" from "a real generic shape." This is the same rule most projects use for extracting a library from an app: prototype in-tree first, extract once ≥2 call sites prove the abstraction. Given F2 shows how much upstream already absorbed without Clan, the bar for Clan specifically should be even higher than for ordinary refactors.

N4. [satisfied] Given F3, DHCP reservations and DNS records for fleet hosts should continue to be authored in the fleet/unified repo's `lib/hosts.nix` (or its successor), which is already the authority for SSH metadata, ingress, and DDNS labels — co-locating network identity with the rest of host identity avoids a second source of truth. The router flake should accept only a narrow, already-shaped input: a list/attrset of `{ name, mac, ip, (zone) }`-type records consumed by `router-dhcp` staticLeases / `router-kea` reservations and the Technitium zone module, exactly as it does today — read-only consumption, no inventory ownership. This confirms round 1 answers that conflated decision 11 with router-flake authority were wrong; the fix is only in how the point is phrased going forward, not in any code change.

</details>

<details>
<summary>DeepSeek (API)</summary>

N1. [satisfied] Top 3 restated: (1) make existing examples/tests *discoverable and trustworthy* — cut GitHub Releases from the existing v0.10.0 tags, add CHANGELOG, README quickstart pointing at `examples/router-single-basic.nix` and `router-ha-pair-example.nix` near the top, CI badge, repo topics, one Discourse/NixOS post; (2) stability contract — semver policy on `services.router-ha`/`router-*` options, deprecation window, documented option surface; (3) docs leading with the typed-topology differentiator, with the HA lab test cited as proof. The gap is *visibility and trust*, not building — F1 shows the artifacts exist but are invisible (no Releases, no changelog, README buries examples). Building more examples is lower value than surfacing what's there.

N2. [satisfied] Move upstream as generic options: MASTER-only unit ownership (generalize the Pangolin/gerbil pattern into `services.router-ha.masterOnlyUnits` or similar); standby guards as declarative booleans (WAN-down, no-Kea/UPnP/DDNS) with the abort fence as a documented transition hook; a generic "role file → zone-HA owner" mechanism (Technitium is one consumer); credential-gating-by-mode as an option. Stay in consumer: `homelab.hosts`→options mapping, the manual-failover `specialisation` (site runbook), NIC/SFP alert rules (hardware-specific), and the specific Technitium/Pangolin wiring. Note `router-security-hardened`'s forced strict `rp_filter` should become an option so loose-rp_filter consumers can enable the rest.

N3. [satisfied] Rule: a *prototype* adapter may live in the consumer with one consumer; a *published, maintained* upstream adapter requires a second independent consumer (or a committed maintainer) before it ships — otherwise it's an unowned liability. This reconciles Codex/Claude with Gemini/DeepSeek: second consumer gates *publication*, not *prototyping*.

N4. [satisfied] Author DHCP reservations and DNS records in the fleet repo's host inventory (the `lib/hosts.nix` authority per F3), not in the router flake. The router flake should accept that inventory as a typed input (host list with SSH/ingress/DDNS labels) and *derive* `router-dhcp` staticLeases, `router-kea` reservations, and Technitium records from it — keeping the dashboard inventory read-only/derived, never authoritative.

</details>

<details>
<summary>OpenCode enrichment seat (big-pickle)</summary>

N1. [satisfied-conditional: maintainers execute the release/docs work and keep existing CI green] Top 3: (1) Make existing examples/tests discoverable: README quickstart near the top, CI badge, links to `examples/` and test commands, repo topics, Discourse post. (2) Build trust: publish GitHub Releases from existing tags, add a top-level changelog/release notes and a compatibility policy. (3) Lead docs with the typed-topology differentiator, pairing each claim with a runnable example and VM test. The gap is visibility/trust, not more examples/tests.

N2. [satisfied-conditional: upstream accepts generic ownership/health-gate options without consumer-specific names] Move upstream: role/ownership gating for MASTER-only units; generic standby health gates and abort-fence semantics; role-driven Technitium zone ownership; hardware-neutral NIC/SFP health/threshold hooks. Stay consumer: `homelab.hosts` mapping, manual-failover specialisation, Pangolin/gerbil-specific units, Kea/UPnP/DDNS site gates, alert destinations/thresholds, credential gating by mode, and loose `rp_filter`/security-hardening policy.

N3. [satisfied-conditional: adapter stays experimental until a second consumer exists] Rule: one consumer is enough to prototype a shape-2 adapter inside that consumer; a second independent consumer is required before publishing it as a maintained upstream adapter or claiming genericity.

N4. [satisfied] The consumer fleet repo’s host list remains the authority: author DHCP reservations and DNS records there, with SSH/ingress/DDNS metadata. The router flake should accept typed reservation/DNS inputs from an adapter, not own fleet inventory; its dashboard inventory stays read-only derived router state.

</details>
