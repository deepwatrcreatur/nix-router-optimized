# Discussion 20: External Architectural Critique Synthesis, Positioning, and Maturation Roadmap

**Status:** closed  
**Scope:** `nix-router-optimized`  
**Date:** 2026-09-16  

## Why this discussion exists

An external architectural review of `nix-router-optimized` by several state-of-the-art chatbots yielded detailed critiques spanning framework identity, evaluation assertions, firewall explainability, hardware offload safety, core routing vs. telemetry decoupling, integration testing, and project maturation.

With over 400 commits, 50+ NixOS modules, and extensive evaluation checks, the repository has reached a critical architectural inflection point. This multi-agent roundtable was convened following the governance protocols in `agent-roundtable` (`docs/design/ORCHESTRATION_GUIDE.md`) to critically evaluate these external critiques, separate accurate diagnoses from stack misunderstandings, form a rigorous consensus, and establish actionable work items for the next development phase.

## Participation Record & Grounding

Following the non-negotiable rules in `agent-roundtable` (`AGENTS.md` & `ORCHESTRATION_GUIDE.md`), all voices represent genuine model executions against a single shared prompt (`/tmp/roundtable_router_critiques_prompt.txt`):

- **DeepSeek API** (DeepSeek-V3 via official direct HTTP endpoint, authenticated with decrypted local agenix key `/home/deepwatrcreatur/.local/share/agenix-user-secrets/deepseek-api-key` and system CA bundle `/etc/ssl/certs/ca-certificates.crt`). Focused on low-level Linux networking, driver capability models, and JSON schema diagnostic contracts.
- **Gemini Pro CLI** (via `agy --dangerously-skip-permissions -p`). Focused on operational router deployment, declarative NixOS abstractions, firewall inspection, and VM smoke topologies.
- **OpenAI Codex CLI** (OpenAI Codex v0.147.0 / `gpt-5.6-sol` via `codex exec`). Focused on low-level kernel socket mechanics, systemd-networkd AST edge cases, nftables rule structure, and failure injection testing.
- **GitHub Copilot CLI** (GitHub Copilot CLI v1.0.79 via `copilot -p --allow-all`). Focused on codebase inspection, developer experience, tool integration, and practical roadmap sequencing.

### Grounding Files Consulted
- `flake.nix`
- `modules/router-optimizations.nix`
- `modules/router-firewall.nix`
- `modules/router-zones.nix`
- `modules/router-networking.nix`
- `modules/router-ha.nix`
- `modules/router-observability.nix`
- `pkgs/router-diag/router-diag.sh`
- `tests/README.md`
- `tests/interface-firewall-invariants.nix`
- `tests/nixos-eval.nix`

---

## Voice Summaries

### 1. DeepSeek API Voice

# Architectural Critique Synthesis: nix-router-optimized

## Q1 — Positioning & Framework Identity

**Verdict: Yes, rebrand. The critique is correct, and the current framing is actively harmful.**

"RouterOS-inspired performance" is a *borrowed* identity. It invites comparison on MikroTik's terms (throughput benchmarks, feature parity with Winbox, hardware appliance pricing) where a NixOS framework will always lose — not because it's worse, but because the comparison is category-mismatched. MikroTik ships a monolithic appliance OS with a GUI; `nix-router-optimized` ships a *declarative composition layer* over NixOS primitives. These are different products.

**The correct positioning** is the one the critique proposes, and it should be sharpened into a one-line thesis:

> *Typed topology → derived firewall/DHCP/DNS/QoS → reproducible deployment → measurable performance.*

Each arrow is a differentiator:

| Stage | What it means | Why it's defensible |
|---|---|---|
| Typed topology | Zones, links, prefixes, pools are Nix types with assertions | Eval-time failure, not runtime failure |
| Derived config | Firewall/DHCP/DNS generated from topology, not hand-written | Single source of truth; no drift |
| Reproducible deploy | `nixos-rebuild switch` on any node, bit-identical | Rollback, audit, CI |
| Measurable perf | Benchmarks are part of the repo, not marketing | Falsifiable claims |

**Differentiation vs. `chayleaf/nixos-router`:** That project is a *single-host router module* — it wires up nftables, dnsmasq/unbound, and a few services with sensible defaults. It is not topology-driven, has no zone abstraction, no multi-node HA story, no eval-time assertion layer, and no compatibility matrix. `nix-router-optimized` should position itself as the *multi-node, topology-typed, assertion-guarded* successor in spirit — not a fork, but a different abstraction level. The honest one-liner:

> *`nixos-router` gives you a router. `nix-router-optimized` gives you a network.*

**Concrete steps:**
1. Rewrite `README.md` and `flake.nix` description to lead with the topology thesis. Remove every "RouterOS" mention except a single historical footnote.
2. Add a `docs/positioning.md` with the four-stage pipeline diagram and an explicit "what we are not" section (not an appliance OS, not a GUI-first product, not a MikroTik replacement).
3. Publish a comparison table against `nixos-router`, `nixos-generators` router examples, and OpenWrt — on axes of *topology typing*, *multi-node*, *eval-time assertions*, *HA*, *test coverage*.

`[satisfied]`

---

## Q2 — Safety, Assertions & Hardware Safety Boundaries

**Eval-time assertions — the immediate set.** These belong in a `lib/assertions.nix` module evaluated from the top-level topology attrset, not scattered through modules. Each should produce a *specific* error message naming the offending zone/link/prefix.

Immediate assertions (all cheap, all pure):

1. **Prefix overlap** — no two `lan`/`guest`/`iot`/`mgmt` prefixes may overlap. Use `lib.network.ipv4CIDR` parsing; reject `10.0.0.0/24` + `10.0.0.128/25`.
2. **DHCP pool containment** — every pool must be a strict subset of its zone prefix, and pools across zones must not overlap.
3. **Duplicate static leases** — no MAC or IP appears twice across all zones.
4. **VRRP VIP uniqueness** — no VIP collides with a static lease, a zone gateway, or another VIP.
5. **Zone reference integrity** — every `allow from X to Y` must reference a declared zone; no dangling names.
6. **MTU consistency** — child interfaces (VLAN, bridge, tunnel) must have MTU ≤ parent; CLAT/DS-Lite interfaces must account for encapsulation overhead.
7. **Interface role uniqueness** — an interface cannot be both `uplink` and `lan`; a bridge member cannot also be a routed interface.
8. **DNS forwarder sanity** — Technitium/Unbound upstreams must not be inside a zone that routes through the router itself (loop detection).
9. **BGP ASN/peer sanity** — local ASN ≠ peer ASN unless explicitly `iBGP = true`; peer addresses must be reachable via a declared link.
10. **HA VIP ↔ VRRP state** — a VIP without a `vrrpInstance` referencing it is an error, and vice versa.

These are all `assert` expressions in a `let` block; they cost nothing at eval and catch the entire class of "I deployed and nothing worked" bugs before `nixos-rebuild` even touches the target.

**Hardware optimization safety boundaries.** The critique's four-state model (`supported` / `enabled` / `effective` / `reason disabled`) is exactly right and should be implemented as a *derivation-time capability probe* plus a *runtime verification*:

- **Supported**: determined at eval time from a `hardware.nic.<driver>` table in `lib/nic-capabilities.nix`. E.g. `virtio_net` supports GRO/GSO/TSO but not XDP-native; `igb` supports all; `r8169` has known BQL issues on some revisions.
- **Enabled**: what the user asked for in `router.optimizations = { gro = true; xdp = false; ... }`.
- **Effective**: what actually took effect — verified by a `routerctl` probe reading `/sys/class/net/<if>/features` and `ethtool -k` at activation time.
- **Reason disabled**: a string explaining *why* (driver doesn't support, kernel version too old, user disabled, conflict with another feature).

The key discipline: **never silently enable**. If `xdp = true` but the NIC is `virtio_net`, the module must either fail eval (strict mode) or emit a warning and record `effective = false, reason = "virtio_net lacks native XDP"`. CAKE is a special case — it's a qdisc, not a NIC feature, so it's always "supported" but its *effectiveness* depends on offload state (CAKE and TSO/GSO interact badly; the module should assert that `cake` on an interface implies `tso = false` on that interface, or warn loudly).

**Concrete steps:**
1. Land `lib/assertions.nix` with the ten assertions above; wire into `flake.nix` checks so `nix flake check` fails on invalid topologies.
2. Land `lib/nic-capabilities.nix` with a driver table covering at minimum: `virtio_net`, `e1000e`, `igb`, `igc`, `r8169`, `mlx4`, `mlx5`, `bnxt`, `ixgbe`.
3. Add `router.optimizations.strict = true|false` — strict fails eval on unsupported, non-strict warns and records.
4. Add a `routerctl hardware` subcommand that dumps the four-state table for every interface.

`[satisfied]`

---

## Q3 — Firewall Explainability & CLI Diagnostics

**Architecture: build on `router-diag`, don't replace it.** The existing tool already knows how to read nftables rulesets; the work is to add a *policy-level* layer above the *ruleset-level* view.

**`routerctl firewall explain`** should be a pure function over the topology attrset, not a runtime nftables query. The reason: the topology is the source of truth, and the explanation should match what the *generator* intended, not what survived a partial reload. Design:

```
routerctl firewall explain --source lan --destination wan --protocol tcp --port 443
```

Implementation:
1. Load the evaluated topology (from `/etc/nix-router/topology.json`, emitted at build time).
2. Walk the zone graph: `lan → wan` requires a `forward` rule; check `allow`/`deny` lists in order.
3. Emit a structured trace:
   ```json
   {
     "verdict": "allow",
     "matched_rule": "zones.lan.forward.allow[2]",
     "rule_text": "tcp dport 443 accept",
     "nftables_chain": "forward_lan_wan",
     "nftables_handle": 42,
     "evaluated_at": "2025-..."
   }
   ```
4. With `--explain-nft`, additionally dump the *actual* nftables rule that implements the decision, so the user can verify the generator did what it claimed.

This dual view — *policy intent* and *kernel reality* — is the whole point. It catches generator bugs (policy says allow, nftables says drop) and drift (someone hand-edited nftables).

**`routerctl status` / `health` / `diagnostics`** should be a single binary with subcommands, emitting JSON by default and a human table with `--format=table`. Structure:

- `routerctl status` — one-shot snapshot: interfaces up/down, addresses, routes, DHCP lease count, DNS query rate, BGP peer state, VRRP state, CAKE qdisc stats. JSON schema versioned.
- `routerctl health` — exit-code-driven checks: `0` healthy, `1` degraded, `2` critical. Each check has an ID (`dhcp.pool.exhausted`, `bgp.peer.down`, `vrrp.split-brain`, `cake.backlog.high`). Designed for Prometheus textfile collector and for `systemd` `ExecCondition`.
- `routerctl diagnostics` — bundle generator: tarball with `status.json`, `health.json`, `nft list ruleset`, `ip -j addr`, `ip -j route`, `ethtool -S` per interface, last 500 journal lines per core unit. Redacts secrets. This is the "attach to bug report" command.

**Why not a web dashboard first:** the critique is right. A dashboard is a *consumer* of structured data; if the structured data doesn't exist, the dashboard is a liability. Build the JSON contract first, then a dashboard is a weekend project. Also: SSH + `jq` works on a 64MB router; a browser does not.

**Concrete steps:**
1. Define JSON schemas in `docs/schemas/` (JSON Schema draft 2020-12) for `status`, `health`, `firewall-explain`.
2. Extend `router-diag` into `routerctl` with the subcommand structure above; keep `router-diag` as a deprecated alias.
3. Emit `topology.json` at build time from the evaluated attrset — this is the input to `firewall explain`.
4. Add `routerctl health --format=prometheus` for node_exporter textfile integration.

`[satisfied]`

---

## Q4 — Core Decoupling & Failure Isolation

**The critique is correct and this is the highest-leverage architectural change.** The current profile-based split is insufficient because a crashing `ntopng` can still exhaust memory, saturate the disk with logs, or (worst case) trigger an OOM that kills `kea` or `unbound`.

**Three-tier model:**

1. **`router-core`** — must never depend on observability or applications. Contains: `systemd-networkd`, `nftables`, `kea`, `unbound`/`technitium`, `keepalived`, `bird`/`frr`, `clatd`/`tayga`, `cake`/`tc`. These run in the host systemd namespace, with `MemoryMin=` reservations and `OOMScoreAdjust=-900` so the kernel prefers to kill anything else first.

2. **`router-observability`** — `ulogd`, `ntopng`, `netdata`, `prometheus-node-exporter`, flow exporters. **Isolation strategy: systemd slices + resource limits, not containers, for the default case.** Rationale:
   - Containers/microVMs add a network namespace, which means the observability tool can't see the host's interfaces without `--network=host` — which defeats the isolation.
   - What we actually want is *resource* isolation, not *namespace* isolation. `systemd` slices with `MemoryMax=`, `CPUQuota=`, `IOWeight=`, and `Slice=router-observability.slice` achieve this.
   - For tools that genuinely need namespace isolation (untrusted exporters, third-party binaries), offer `router.observability.<tool>.isolation = "container"` as an opt-in that runs the tool in a `systemd-nspawn` container with `--network=host` and a read-only bind of `/proc/net`.
   - **MicroVMs are overkill** for a router. They cost 50–100MB RAM each and add boot complexity. Reserve them for the "I want to run untrusted third-party code" case, which is rare.

3. **`router-applications`** — `caddy`, `wireguard` admin tunnels, `tailscale`, remote admin. These *do* warrant namespace isolation because they're user-facing and often third-party. Default to `systemd-nspawn` containers with their own network namespace, routed through the core via a veth pair. This is the one place where the container tax is worth paying.

**Failure isolation guarantees to encode:**
- `router-observability.slice` has `MemoryMax=256M` by default; if it OOMs, core is untouched.
- `router-applications.slice` has `MemoryMax=512M` and `CPUQuota=50%`.
- Core units have `Restart=always`, `RestartSec=1`, and `StartLimitBurst=0` (never give up).
- Observability units have `Restart=on-failure` with backoff; if they crash-loop, they stay down and `routerctl health` reports `observability.degraded` — but core health stays green.

**Concrete steps:**
1. Define three slices in `modules/core/slices.nix` with the resource limits above.
2. Audit every module: tag it `core`, `observability`, or `application`; assert no `core` module imports an `observability` or `application` module.
3. Add `router.profile = "core" | "core+obs" | "full"` as the top-level switch; `core` must fit in 128MB RAM.
4. Add a CI test that boots a `core`-only VM and asserts `systemctl list-units --state=running` contains no observability units.

`[satisfied]`

---

## Q5 — Automated NixOS VM Integration Tests & Compatibility Matrix

**Test topology.** The critique's `client <--> router <--> wanSimulator` is the right shape. Concretely, in `tests/`:

```
tests/
  lib/
    mkTopology.nix        # shared VM builders
    wanSim.nix            # a VM that acts as upstream ISP: DHCP server, DNS, HTTP, BGP peer
  dhcp/
    basic.nix             # client gets lease, can ping router, can reach wanSim
    pool-exhaustion.nix   # N clients, N+1th gets NAK
    static-lease.nix      # MAC-matched client gets fixed IP
  firewall/
    zone-isolation.nix    # guest cannot reach lan; lan can reach guest
    port-forward.nix      # wanSim -> router:443 -> lan:8443
    stateful.nix          # established/related works, invalid dropped
  nat/
    masquerade.nix        # client -> wanSim, source is router WAN IP
    nat64.nix             # IPv6-only client reaches IPv4 wanSim via CLAT/DNS64
  ha/
    vrrp-failover.nix     # two routers, kill master, VIP moves, client traffic resumes <2s
    vrrp-split-brain.nix  # partition, assert no dual-master
  dns/
    unbound-forward.nix   # client resolves via router, upstream is wanSim
    technitium-block.nix  # blocked domain returns NXDOMAIN
  qos/
    cake-latency.nix      # saturate link, assert p99 latency < 10ms
  bgp/
    peer-up.nix           # router peers with wanSim, advertises LAN prefix
    peer-down.nix         # wanSim withdraws, router removes route
```

Each test is a `nixosTest` with `nodes.client`, `nodes.router`, `nodes.wanSim`. Use `testScript` with `client.wait_for_unit("network-online.target")` and `client.succeed("ping -c1 10.0.0.1")`. For timing-sensitive tests (HA failover, CAKE latency), use `client.wait_until_succeeds` with a timeout and assert on the *duration*.

**Critical addition the critique missed:** a **negative test** suite. Assert that invalid topologies *fail eval* — `nix-instantiate --eval` on a topology with overlapping prefixes must exit non-zero with a specific message. This is how you prevent assertion regressions.

**Compatibility matrix.** Initial axes:

| Axis | Values | Status |
|---|---|---|
| Arch | `x86_64-linux`, `aarch64-linux` | Both must pass full test suite |
| Platform | QEMU VM, bare metal | VM in CI; bare metal via `nixos-rebuild test` on reference hardware |
| NIC driver | `virtio_net`, `igb`, `igc`, `r8169`, `mlx5` | `virtio_net` in CI; others via hardware-in-loop runners |
| IP version | IPv4-only, IPv6-only, dual-stack | All three in CI |
| WAN type | DHCP, static, PPPoE, DS-Lite | DHCP + static in CI; PPPoE/DS-Lite manual |
| HA | single-node, VRRP pair | Both in CI |
| Profile | `core`, `core+obs`, `full` | All three in CI |

Publish as `docs/compatibility.md` with a CI badge per cell. Cells that are "manual" get a documented procedure and a known-good hardware list.

**Concrete steps:**
1. Land `tests/lib/mkTopology.nix` and the `dhcp/basic.nix` test as a proof of concept.
2. Add `checks.<system>.integration` to `flake.nix` so `nix flake check` runs the suite.
3. Add a `checks.<system>.eval-negative` suite for assertion tests.
4. Stand up a hardware-in-loop runner (a NUC + a managed switch + a second NUC as wanSim) for `igb`/`igc`/`r8169` validation.
5. Publish `docs/compatibility.md` with the matrix above.

`[satisfied-conditional: hardware-in-loop runner is provisioned for non-virtio NIC validation]`

---

## Q6 — Roadmap & Work Item Priorities

**Yes, support a feature freeze — with a hard boundary.** The critique is right that the project has crossed the threshold where *more features* actively reduce quality. 400 commits and 50+ modules without a full integration test suite is a liability, not an achievement. Freeze new feature modules for **two release cycles** (or ~90 days, whichever is longer), with a narrow exception process: a feature may land during freeze only if it is required to *test* or *assert* an existing feature.

**Immediate work items, in priority order:**

**P0 — Safety net (weeks 1–3):**
1. `lib/assertions.nix` with the ten assertions from Q2. Wire into `flake.nix` checks.
2. `tests/lib/mkTopology.nix` + `dhcp/basic.nix` + `firewall/zone-isolation.nix`. Prove the harness works.
3. `routerctl status` and `routerctl health` with JSON output. This is the observability primitive everything else builds on.
4. `docs/positioning.md` and README rewrite. Positioning is cheap and unblocks everything else.

**P1 — Isolation & diagnostics (weeks 4–8):**
5. Three-tier slice architecture from Q4. Audit every module's tier.
6. `routerctl firewall explain` with `topology.json` emission.
7. `routerctl diagnostics` bundle generator.
8. `lib/nic-capabilities.nix` + `router.optimizations.strict`.

**P2 — Test coverage & matrix (weeks 9–16):**
9. Full `tests/` suite from Q5: NAT, HA, DNS, QoS, BGP.
10. Negative eval test suite.
11. `docs/compatibility.md` with CI badges.
12. Hardware-in-loop runner for non-virtio NICs.

**P3 — Performance & polish (weeks 17–24):**
13. Benchmark suite: `iperf3` throughput, `flent`/`irtt` latency under load, CAKE effectiveness, XDP pps. Publish numbers in `docs/benchmarks.md`.
14. `routerctl hardware` four-state table.
15. Deprecation pass: remove legacy `networking.nat.*` usage, standardize on `networking.nftables.enable = true` and `systemd-networkd`.

**Explicitly deferred (post-freeze):**
- Web dashboard.
- New protocol support (OSPF, WireGuard mesh automation).
- Additional observability integrations.
- Anything that adds a module without a corresponding test.

**Concrete steps:**
1. Open a `FREEZE.md` at repo root with the freeze policy, exception process, and end date.
2. Create GitHub milestones P0–P3 with the items above; pin P0 to the next release.
3. Add a CI gate: any PR adding a new module without a test file fails.
4. Publish a monthly "freeze progress" note in `docs/`.

`[satisfied]`

---

## Summary

The critique is largely correct and technically sound. The two places it under-specifies are (a) the *isolation mechanism* for observability — slices, not containers, for the default case — and (b) the need for *negative* eval tests, not just positive integration tests. The two places it over-reaches are minor: "containerize peripheral observability" is too strong as a default, and "stop adding features" needs a narrow exception for test-enabling work. Everything else — rebranding, assertions, `routerctl`, three-tier decoupling, VM test topology, compatibility matrix, feature freeze — should be adopted essentially as written.

The single highest-leverage change is `lib/assertions.nix`. It converts an entire class of runtime failures into eval-time failures, costs nothing at runtime, and is the foundation on which the topology-typed positioning claim rests. Do that first.

---

### 2. Gemini Pro CLI Voice (via `agy`)

# Discussion 20: Architectural Critique Synthesis, Positioning, and Maturation Roadmap

**Scope:** `nix-router-optimized`  
**Round:** Multi-Agent Deliberation & External Critique Synthesis  
**Grounding Sources:**  
- [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix)
- [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix)
- [router-firewall.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-firewall.nix)
- [router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix)
- [router-networking.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-networking.nix)
- [router-ha.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-ha.nix)
- [router-observability.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-observability.nix)
- [router-diag.sh](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/pkgs/router-diag/router-diag.sh)
- [tests/README.md](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/tests/README.md)

---

### Executive Overview & Critique Audit

The external review highlights crucial inflection points as `nix-router-optimized` transitions from a rapid-prototyping phase (over 400 commits, 50+ modules, 93 work items) into a hardened production router distribution.

While parts of the external critique accurately diagnose our architectural debt (e.g., lack of QEMU VM tests, unconstrained hardware offload flags, and monorepo coupling of core vs. observability), other parts misunderstand our stack (e.g., presuming we use legacy `networking.nat.*` or scripted networking, when we are already 100% native `systemd-networkd` and pure `nftables`).

Below is the technical evaluation across all six discussion questions.

---

### Q1 (Positioning & Framework Identity)

#### 1. Technical Analysis
- **What the critique got right:**
  - Emphasizing *"RouterOS-like performance"* in our top-level identity ([flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix#L2) and [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L1)) is a major positioning liability. MikroTik RouterOS is a proprietary network operating system featuring a vendor-specific fastpath packet engine. In our repo, "RouterOS-inspired" was historically used as shorthand for kernel conntrack tuning and flowtable offloading. In practice, it sounds like benchmark vanity and distracts from the core engineering value of the project.
  - The framework's true value proposition is: **typed network topology $\rightarrow$ derived nftables/networkd/DHCP/DNS configuration $\rightarrow$ deterministic edge deployment $\rightarrow$ verifiable performance**.
- **What the critique misunderstood:**
  - The critique framed the project as if it were simply a collection of kernel sysctl tweaks and performance scripts. In reality, the codebase contains sophisticated protocol engines—such as declarative 464XLAT/CLAT control planes ([router-clat.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-clat.nix)), VRRP HA with BGP neighbor promotion and WAN MAC cloning ([router-ha.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-ha.nix)), and Kea HA synchronization.
- **Exact Technical Differentiation against `chayleaf/nixos-router`:**
  1. **Stack Philosophy (`systemd-networkd` vs. Scripted Netns):**
     - `chayleaf/nixos-router` is built around network namespaces (`router.networkNamespaces`) and custom scripted networking wrapper commands, explicitly rejecting `systemd-networkd` due to historical limitations.
     - `nix-router-optimized` standardizes strictly on upstream declarative **`systemd-networkd`** ([router-networking.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-networking.nix)) and pure declarative **`nftables`** ([router-firewall.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-firewall.nix)), maintaining full alignment with mainstream NixOS evolution.
  2. **Abstraction Level (Complete Router Appliance vs. Low-Level NFT DSL):**
     - `chayleaf/nixos-router` expects operators to write raw nftables rules or use its `notnft` JSON DSL from scratch; it does not generate zone firewalls, MSS clamping, or NAT rules automatically.
     - `nix-router-optimized` provides a **declarative forward-only zone firewall** ([router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix)), automatic hairpin NAT, SYN proxying, bogon filtering, and RFC 8028 multi-homing.
  3. **Multi-Protocol Edge Services:**
     - `nix-router-optimized` includes first-class integrated modules for BGP (FRR), stateful Kea DHCP, Technitium/Unbound DNS with split-horizon overrides, CAKE SQM, and active-passive VRRP HA failover out-of-the-box.

#### 2. Concrete Technical Steps
1. Rebrand the project in [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix) and [README.md](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/README.md) to:
   > *"A typed, topology-driven declarative router framework for NixOS: Deterministic edge networking, zone security, and resilient protocol orchestration."*
2. Deprecate claims of "RouterOS emulation"; re-label [modules/router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix) to `router-kernel-tuning.nix`.

**Satisfaction:** `[satisfied]`

---

### Q2 (Safety, Assertions & Hardware Safety Boundaries)

#### 1. Technical Analysis
- **What the critique got right:**
  - **Dangerous Offload Blindness:** In [modules/router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L203-L209), the module executes:
    ```bash
    ethtool -K $iface gro on 2>/dev/null || true
    ethtool -K $iface lro on 2>/dev/null || true
    ```
    **Enabling LRO (Large Receive Offload) on a forwarding router is a critical networking violation.** In Linux, LRO aggregates TCP segments without preserving transport header checksums or packet boundaries, which silently breaks routing, corrupts forwarded TCP streams, and degrades NAT/conntrack. GRO is safe for routing; LRO is hostile to forwarding.
  - **Evaluation Gap:** Currently, assertions in [router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix#L133-L164) only verify zone naming and interface uniqueness. There are no build-time assertions preventing overlapping subnets, DHCP pool misallocations, or MTU mismatches.
- **What the critique misunderstood:**
  - The critique implies that NIC hardware capabilities should be checked during Nix evaluation. However, Nix evaluation is hermetic and occurs on the build host, which has no access to the target machine's sysfs, PCI bus, or `ethtool` state. Hardware capability boundaries must be split into:
    1. **Evaluation-time logical invariants** (pure Nix).
    2. **Runtime capability negotiation & driver guardrails** (systemd activation).

#### 2. Concrete Technical Steps
1. **Immediate Nix Evaluation-Time Assertions:**
   - **Subnet Overlap Assertion:** Add a Nix CIDR calculator in `modules/lib/ip.nix` that checks all IPv4 and IPv6 prefixes across `services.router-networking.routedInterfaces` and asserts pairwise non-overlap.
   - **DHCP Pool Subnet Enclosure:** Assert that all defined Kea/systemd DHCP pools fall strictly within the CIDR prefix of the bound interface.
   - **VLAN vs. Parent MTU Invariant:** For every VLAN interface defined with a parent device, assert `vlan.mtu <= parent.mtu`.
   - **VRRP VIP Separation:** In `services.router-ha`, assert that the VRRP virtual IP does not match the physical static IP of either the master or backup node on that segment.
2. **Hardware Safety Matrix & Safe Offload Guardrails:**
   - **Remove `lro on` immediately** from [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L206). Replace with an explicit `ethtool -K $iface lro off`.
   - Replace blind `|| true` bash commands with a capability inspection script:
     ```bash
     apply_offload() {
       local dev="$1" feat="$2" state="$3"
       if ethtool -k "$dev" 2>/dev/null | grep -q "^${feat}:.*\[fixed\]"; then
         echo "Notice: ${feat} on ${dev} is fixed by driver; cannot force ${state}"
       else
         ethtool -K "$dev" "$feat" "$state" || true
       fi
     }
     ```
   - Model optimization profiles explicitly:
     `services.router-optimizations.profile = "intel-baremetal" | "realtek-baremetal" | "virtio-vm" | "generic"`. In `virtio-vm`, disable hardware TSO/GSO manipulation and leave offloads to hypervisor virtio-net defaults.
   - Emit an operational state file at `/run/router/nic-offload-status.json` recording `[feature, requested, driver_status, effective]`.

**Satisfaction:** `[satisfied]`

---

### Q3 (Firewall Explainability & CLI Diagnostics)

#### 1. Technical Analysis
- **What the critique got right:**
  - The current diagnostic tool in [pkgs/router-diag/router-diag.sh](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/pkgs/router-diag/router-diag.sh) is a basic 120-line bash script that prints ANSI-colored terminal text. It has no structured JSON output, making it impossible to integrate with automated remote monitoring or scripting.
  - As policy complexity grows (flowtables, fasttrack bypasses, zone-to-zone rules, port forwardings), operators cannot easily trace why a packet was dropped or accepted without wading through `nft list ruleset`.
- **What the critique misunderstood:**
  - A tool like `routerctl firewall explain` cannot simply invoke an nftables CLI flag to simulate packet traversal, because Linux `nftables` does not possess an offline packet-tracer engine (unlike proprietary ASIC appliances like Cisco ASA).
  - Simulating packet traversal must therefore be handled either by querying our declarative policy graph or by configuring active kernel trace probes.

#### 2. Concrete Technical Architecture for `routerctl`
1. **Transition from `router-diag.sh` to structured `routerctl`:**
   - Implement `routerctl` with subcommands: `status`, `health`, `interfaces`, `firewall`, `bgp`, `ha`.
   - Every subcommand must support `--json` (e.g., `routerctl health --json`, `routerctl interfaces --json`).
2. **`routerctl firewall explain` Two-Tier Implementation:**
   - **Tier 1: Static Policy Graph Evaluation (Zero-packet dry run):**
     - During Nix evaluation, export the compiled zone matrix from `services.router-zones` into `/etc/router/policy-manifest.json`:
       ```json
       {
         "zones": { "lan": ["br-lan"], "wan": ["eth0"], "iot": ["vlan20"] },
         "policies": [
           { "from": "lan", "to": "wan", "action": "accept" },
           { "from": "iot", "to": "lan", "action": "drop" }
         ]
       }
       ```
     - `routerctl firewall explain --src-iface vlan20 --dst-iface eth0 --proto tcp --dport 443`:
       1. Resolves `vlan20` $\rightarrow$ zone `iot`, `eth0` $\rightarrow$ zone `wan`.
       2. Looks up `iot` $\rightarrow$ `wan` in the policy manifest.
       3. Outputs:
          ```text
          Source Zone:      iot (via interface vlan20)
          Destination Zone: wan (via interface eth0)
          Zone Forward:     ALLOW (matched policy 'iot->wan')
          MSS Clamping:     ENABLED (WAN egress MTU 1500 -> 1452)
          Flowtable Offload: ACTIVE (TCP established packets bypass CPU)
          Matching Chain:   zone_iot_forward -> oifname "eth0" accept
          ```
   - **Tier 2: Ephemeral `nftrace` Trace Runner (`--live`):**
     - When invoked as `routerctl firewall trace --src 10.0.10.50 --dst 1.1.1.1 --dport 53`:
       1. Installs a transient high-priority rule in the `raw` / `prerouting` chain: `meta nftrace set 1`.
       2. Streams trace events via `nft monitor trace` for 5 seconds.
       3. Parses and prints the exact chains traversed (`filter forward`, `zone_lan_forward`, `nat postrouting`) before cleaning up the trace rule.

**Satisfaction:** `[satisfied]`

---

### Q4 (Core Decoupling & Failure Isolation)

#### 1. Technical Analysis
- **What the critique got right:**
  - In [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix#L72-L100), `nixosModules.default` imports over 25 heterogeneous modules, including `caddy-reverse-proxy`, `router-homelab`, `router-observability`, `router-tunnels`, and `router-remote-admin`. While they are gated by `mkEnableOption`, grouping them into a monolithic module blurs the line between routing critical path and auxiliary appliances.
  - In [modules/router-observability.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-observability.nix#L60-L67), `services.ulogd` hard-codes paths to six C dynamic plugins (`.so`). An upstream nixpkgs update that reorganizes `pkgs.ulogd` or bumps a library dependency can break `ulogd.service`.
  - A resource leak in `ntopng`, `suricata`, or `netdata` must never exhaust system memory or cause the Linux OOM-killer to terminate `systemd-networkd`, `kea`, or `named/technitium`.
- **What the critique misunderstood:**
  - Recommending "NixOS microVMs" (MicroVM.nix) to isolate observability tools on edge routers is counterproductive for low-power edge hardware (e.g. 2GB–4GB RAM appliances). Running multiple QEMU/microVM instances introduces double networking hops, vhost-net memory overhead, and severe CPU cache thrashing.
  - Similarly, running `ulogd` inside an unprivileged container creates socket friction because NFLOG packet capture requires raw `NETLINK_NETFILTER` sockets in the host network namespace.

#### 2. Concrete Architectural Architecture
1. **Tiered Flake Module Composition:**
   Split the monolithic module exports in [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix) into three strictly isolated profiles:
   - `nixosModules.profile-core`: Routing, nftables firewall, `systemd-networkd`, Kea/systemd DHCP, Technitium/Unbound DNS, CAKE SQM, VRRP HA. (Zero telemetry, zero Web UIs).
   - `nixosModules.profile-observability`: `ulogd2`, Vector, Prometheus Node Exporter, packet capture hooks.
   - `nixosModules.profile-homelab`: Caddy reverse proxy, Netdata, Grafana, Speedtest-tracker, Tailscale/ZeroTier tunnels.
2. **Systemd Slicing & CGroup Quotas:**
   Enforce failure isolation using systemd cgroups rather than microVMs:
   - Define `router-core.slice`:
     `CPUWeight=1000`, `CPUSchedulingPolicy=rr` (or `other`), `OOMScoreAdjust=-900`.
     All core daemons (`systemd-networkd`, `kea`, `technitium`, `keepalived`) bind to this slice.
   - Define `router-observability.slice`:
     `CPUWeight=100`, `MemoryMax=512M`, `MemoryHigh=384M`, `OOMScoreAdjust=500`.
     `ulogd`, `vector`, and Prometheus collectors bind here.
   - Define `router-apps.slice`:
     `CPUWeight=50`, `MemoryMax=1G`, `OOMScoreAdjust=800`.
     Caddy, Netdata, and ntopng bind here.
3. **Observability Failure Immunity:**
   - Configure `ulogd.service` with `Restart=always`, `RestartSec=5s`.
   - In nftables, configure NFLOG packet output with `flags nflog-size 128` and non-blocking drops: if `ulogd` dies, kernel netlink queues drop telemetry packets silently without stalling the forward chain.
   - Add a Nix build check (`checks.ulogd-plugins`) verifying that all specified `.so` paths in `pkgs.ulogd` exist in the store derivation before producing the closure.

**Satisfaction:** `[satisfied]`

---

### Q5 (Automated NixOS VM Integration Tests & Compatibility Matrix)

#### 1. Technical Analysis
- **What the critique got right:**
  - As recorded in [tests/README.md](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/tests/README.md#L7-L8), all 22 existing checks in the repository are `mkNixosEvalCheck` evaluation tests. They evaluate `system.build.toplevel` for option conflicts and assertions, but **zero runtime integration tests** are executed.
  - We currently have no automated verification that a booted kernel loads nftables rulesets without syntax errors, that `systemd-networkd` properly binds interfaces, that Kea DHCP actually leases IPs over the wire, or that CAKE SQM handles packets without dropping link state.
- **What the critique misunderstood:**
  - Running bloated multi-node QEMU tests for every minor commit in GitHub Actions causes long queue times and intermittent timing failures.
  - VM tests must be structured into a lightweight, fast **Smoke Test Suite** (running on PRs) and a comprehensive **Protocol Test Suite** (running nightly or pre-release).

#### 2. Virtual Multi-Node Test Topology (`tests/vm/`)
Implement `tests/vm/router-basic-smoke.nix` using `pkgs.testers.runNixOSTest`:

```
+-------------------+           +-----------------------+           +-------------------+
|   wanSimulator    |           | nix-router-optimized  |           |      client       |
|                   |  eth-wan  |                       |  eth-lan  |                   |
| 198.51.100.1/24   |<=========>| WAN: DHCP Client      |<=========>| LAN: DHCP Client  |
| DHCPv4/v6 Server  |  (VLAN 1) | LAN: 10.0.10.1/24     |  (VLAN 2) | Expected IP:      |
| DNS Root Stub     |           | Zone: wan <-> lan     |           | 10.0.10.x/24      |
+-------------------+           +-----------------------+           +-------------------+
```

- **Test Script Steps (`testScript`):**
  1. `wanSimulator.wait_for_unit("kea-dhcp4-server")`
  2. `router.wait_for_unit("network-online.target")`
  3. `client.wait_for_unit("network-online.target")`
  4. Assert `client` receives an IP from `router` via DHCP and default route pointing to `10.0.10.1`.
  5. `client.succeed("ping -c 2 10.0.10.1")` (LAN gateway connectivity).
  6. `client.succeed("ping -c 2 198.51.100.1")` (Verify NAT masquerade across `router`).
  7. `client.succeed("host router.internal 10.0.10.1")` (Verify local DNS resolution).
  8. **Firewall Isolation Invariant:** Connect a fourth node `iotNode` on `eth-iot` (`10.0.20.0/24`); assert `iotNode.fail("ping -c 2 10.0.10.x -W 1")` (confirming `router-zones` drop policy).

#### 3. Initial Hardware & Platform Compatibility Matrix

| Tier | Architecture | Target Platforms / Drivers | Testing Method | Support Level & Features |
|---|---|---|---|---|
| **Tier 1 (Core)** | `x86_64-linux` | Proxmox / KVM (`virtio-net`) | Automated NixOS QEMU VM Tests | Fully supported: Routing, NAT, Flowtables, Zones, Kea, Technitium, HA |
| **Tier 1 (Bare Metal)**| `x86_64-linux` | Intel NICs (`e1000e`, `igb`, `igc`, `ixgbe`) | Hardware Lab Benchmarks | Fully supported: CAKE SQM, GRO/TSO, BBR, Hardware Coalescing, Multi-queue RSS |
| **Tier 2 (SBC)** | `aarch64-linux` | RK3588 (NanoPi R6S), Raspberry Pi 5 | Eval checks + Manual Release Testing | Supported: Core routing, pure nftables, CAKE SQM (offloads constrained) |
| **Tier 3 (Budget)** | `x86_64-linux` | Realtek PCIe/USB (`r8169`, `r8152`) | Community Tested | Constrained: TSO/GSO disabled, basic SQM only, single-queue |

**Satisfaction:** `[satisfied]`

---

### Q6 (Roadmap & Work Item Priorities)

#### 1. Technical Analysis
- **Do we support a temporary feature freeze?**
  - **YES, strongly support an immediate "Maturation & Hardening Freeze".**
  - The repository has amassed over 50 modules, spanning BGP, CLAT/NAT64, NDP proxy, Keepalived HA, Technitium clustering, and multiple VPN overlays. Adding further major network features (such as OSPF, EVPN/VXLAN, or additional UI tabs) before addressing test automation and hardware boundaries would compound architectural debt.
  - The freeze should specifically halt new network service abstractions while actively prioritizing:
    1. Comprehensive eval-time assertions.
    2. Automated NixOS QEMU VM integration testing.
    3. Hardware safety boundaries in kernel tuning.
    4. Structured machine-readable diagnostics (`routerctl`).

#### 2. Immediate Work Item Schedule (Docs/Work-Items Format)

The following work items are scheduled to execute this maturation roadmap:

```
+---------------------------------------------------------------------------------------+
| MATURATION SPRINT SCHEDULE                                                            |
+---------+-------------------------------------------------------------+--------------+
| Item ID | Title & Scope                                               | Priority     |
+---------+-------------------------------------------------------------+--------------+
| WI-94   | Subnet Overlap, MTU & Topology Invariant Assertions         | P0 (Blocker) |
| WI-95   | Hardware Optimization Safety Matrix & LRO Removal           | P0 (Blocker) |
| WI-96   | Multi-Node NixOS VM Test Harness (client <-> router <-> wan) | P0 (Blocker) |
| WI-97   | `routerctl` CLI Diagnostics & Static Firewall Explainer     | P1 (High)    |
| WI-98   | Systemd Slice Resource Isolation & Tiered Profile Split     | P1 (High)    |
| WI-99   | Decouple Flake Outputs & Rebrand Framework Identity         | P2 (Medium)  |
+---------+-------------------------------------------------------------+--------------+
```

1. **Work Item 94: Subnet Overlap, MTU & Topology Invariant Assertions**
   - Implement `modules/lib/ip.nix` with pure Nix CIDR calculation.
   - Enforce build-time failure if routed interfaces overlap, if DHCP pools exceed interface subnets, or if VLAN MTU exceeds parent MTU.
2. **Work Item 95: Hardware Optimization Safety Matrix & LRO Removal**
   - Purge `lro on` from [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix).
   - Implement driver-aware capability checks via `ethtool -k` before applying offload modifications.
   - Generate `/run/router/nic-offload-status.json`.
3. **Work Item 96: Multi-Node NixOS VM Test Harness**
   - Establish `tests/vm/` using `pkgs.testers.runNixOSTest`.
   - Implement `minimal-router-smoke.nix` testing DHCP acquisition, NAT packet traversal, DNS forwarding, and zone drop isolation in headless QEMU.
4. **Work Item 97: `routerctl` Structured CLI Diagnostics & Static Firewall Explainer**
   - Refactor `pkgs/router-diag` to output structured JSON via `routerctl --json`.
   - Implement `routerctl firewall explain --src <iface> --dst <iface>` backed by `/etc/router/policy-manifest.json`.
5. **Work Item 98: Systemd Slice Resource Isolation & Tiered Profile Split**
   - Separate modules in `flake.nix` into `profile-core`, `profile-observability`, and `profile-homelab`.
   - Apply `systemd.slices` (`router-core.slice` vs `router-observability.slice`) with strict memory/CPU quotas and failure isolation for `ulogd` and monitoring daemons.

**Satisfaction:** `[satisfied]`

---

### Summary of Roundtable Verdicts

| Question | Topic | Verdict | Next Operational Milestone |
|---|---|---|---|
| **Q1** | Positioning & Rebranding | `[satisfied]` | Rebrand to "Typed Topology-Driven NixOS Router"; update flake metadata |
| **Q2** | Invariant Assertions & Safe Offloads | `[satisfied]` | Strip `lro on`, implement IP CIDR overlap checks |
| **Q3** | `routerctl` & Policy Explainability | `[satisfied]` | Add `--json` flag and export declarative zone policy graph |
| **Q4** | Core Decoupling & Failure Slicing | `[satisfied]` | Isolate telemetry into `router-observability.slice` with memory bounds |
| **Q5** | Automated QEMU VM Integration Tests | `[satisfied]` | Land 3-node `wanSimulator <-> router <-> client` test in `tests/vm/` |
| **Q6** | Feature Freeze & Work Item Roadmap | `[satisfied]` | Freeze new service modules; schedule Work Items 94 through 99 |

---

### 3. OpenAI Codex CLI Voice

## Q1 — Positioning & Framework Identity

**Verdict: Yes, rebrand. The critique is correct, and the current framing is actively harmful.**

"RouterOS-inspired performance" is a *borrowed* identity. It invites comparison on MikroTik's terms (throughput benchmarks, feature parity with Winbox, hardware appliance pricing) where a NixOS framework will always lose — not because it's worse, but because the comparison is category-mismatched. MikroTik ships a monolithic appliance OS with a GUI; `nix-router-optimized` ships a *declarative composition layer* over NixOS primitives. These are different products.

**The correct positioning** is the one the critique proposes, and it should be sharpened into a one-line thesis:

> *Typed topology → derived firewall/DHCP/DNS/QoS → reproducible deployment → measurable performance.*

Each arrow is a differentiator:

| Stage | What it means | Why it's defensible |
|---|---|---|
| Typed topology | Zones, links, prefixes, pools are Nix types with assertions | Eval-time failure, not runtime failure |
| Derived config | Firewall/DHCP/DNS generated from topology, not hand-written | Single source of truth; no drift |
| Reproducible deploy | `nixos-rebuild switch` on any node, bit-identical | Rollback, audit, CI |
| Measurable perf | Benchmarks are part of the repo, not marketing | Falsifiable claims |

**Differentiation vs. `chayleaf/nixos-router`:** That project is a *single-host router module* — it wires up nftables, dnsmasq/unbound, and a few services with sensible defaults. It is not topology-driven, has no zone abstraction, no multi-node HA story, no eval-time assertion layer, and no compatibility matrix. `nix-router-optimized` should position itself as the *multi-node, topology-typed, assertion-guarded* successor in spirit — not a fork, but a different abstraction level. The honest one-liner:

> *`nixos-router` gives you a router. `nix-router-optimized` gives you a network.*

**Concrete steps:**
1. Rewrite `README.md` and `flake.nix` description to lead with the topology thesis. Remove every "RouterOS" mention except a single historical footnote.
2. Add a `docs/positioning.md` with the four-stage pipeline diagram and an explicit "what we are not" section (not an appliance OS, not a GUI-first product, not a MikroTik replacement).
3. Publish a comparison table against `nixos-router`, `nixos-generators` router examples, and OpenWrt — on axes of *topology typing*, *multi-node*, *eval-time assertions*, *HA*, *test coverage*.

`[satisfied]`

---

## Q2 — Safety, Assertions & Hardware Safety Boundaries

**Eval-time assertions — the immediate set.** These belong in a `lib/assertions.nix` module evaluated from the top-level topology attrset, not scattered through modules. Each should produce a *specific* error message naming the offending zone/link/prefix.

Immediate assertions (all cheap, all pure):

1. **Prefix overlap** — no two `lan`/`guest`/`iot`/`mgmt` prefixes may overlap. Use `lib.network.ipv4CIDR` parsing; reject `10.0.0.0/24` + `10.0.0.128/25`.
2. **DHCP pool containment** — every pool must be a strict subset of its zone prefix, and pools across zones must not overlap.
3. **Duplicate static leases** — no MAC or IP appears twice across all zones.
4. **VRRP VIP uniqueness** — no VIP collides with a static lease, a zone gateway, or another VIP.
5. **Zone reference integrity** — every `allow from X to Y` must reference a declared zone; no dangling names.
6. **MTU consistency** — child interfaces (VLAN, bridge, tunnel) must have MTU ≤ parent; CLAT/DS-Lite interfaces must account for encapsulation overhead.
7. **Interface role uniqueness** — an interface cannot be both `uplink` and `lan`; a bridge member cannot also be a routed interface.
8. **DNS forwarder sanity** — Technitium/Unbound upstreams must not be inside a zone that routes through the router itself (loop detection).
9. **BGP ASN/peer sanity** — local ASN ≠ peer ASN unless explicitly `iBGP = true`; peer addresses must be reachable via a declared link.
10. **HA VIP ↔ VRRP state** — a VIP without a `vrrpInstance` referencing it is an error, and vice versa.

These are all `assert` expressions in a `let` block; they cost nothing at eval and catch the entire class of "I deployed and nothing worked" bugs before `nixos-rebuild` even touches the target.

**Hardware optimization safety boundaries.** The critique's four-state model (`supported` / `enabled` / `effective` / `reason disabled`) is exactly right and should be implemented as a *derivation-time capability probe* plus a *runtime verification*:

- **Supported**: determined at eval time from a `hardware.nic.<driver>` table in `lib/nic-capabilities.nix`. E.g. `virtio_net` supports GRO/GSO/TSO but not XDP-native; `igb` supports all; `r8169` has known BQL issues on some revisions.
- **Enabled**: what the user asked for in `router.optimizations = { gro = true; xdp = false; ... }`.
- **Effective**: what actually took effect — verified by a `routerctl` probe reading `/sys/class/net/<if>/features` and `ethtool -k` at activation time.
- **Reason disabled**: a string explaining *why* (driver doesn't support, kernel version too old, user disabled, conflict with another feature).

The key discipline: **never silently enable**. If `xdp = true` but the NIC is `virtio_net`, the module must either fail eval (strict mode) or emit a warning and record `effective = false, reason = "virtio_net lacks native XDP"`. CAKE is a special case — it's a qdisc, not a NIC feature, so it's always "supported" but its *effectiveness* depends on offload state (CAKE and TSO/GSO interact badly; the module should assert that `cake` on an interface implies `tso = false` on that interface, or warn loudly).

**Concrete steps:**
1. Land `lib/assertions.nix` with the ten assertions above; wire into `flake.nix` checks so `nix flake check` fails on invalid topologies.
2. Land `lib/nic-capabilities.nix` with a driver table covering at minimum: `virtio_net`, `e1000e`, `igb`, `igc`, `r8169`, `mlx4`, `mlx5`, `bnxt`, `ixgbe`.
3. Add `router.optimizations.strict = true|false` — strict fails eval on unsupported, non-strict warns and records.
4. Add a `routerctl hardware` subcommand that dumps the four-state table for every interface.

`[satisfied]`

---

## Q3 — Firewall Explainability & CLI Diagnostics

**Architecture: build on `router-diag`, don't replace it.** The existing tool already knows how to read nftables rulesets; the work is to add a *policy-level* layer above the *ruleset-level* view.

**`routerctl firewall explain`** should be a pure function over the topology attrset, not a runtime nftables query. The reason: the topology is the source of truth, and the explanation should match what the *generator* intended, not what survived a partial reload. Design:

```
routerctl firewall explain --source lan --destination wan --protocol tcp --port 443
```

Implementation:
1. Load the evaluated topology (from `/etc/nix-router/topology.json`, emitted at build time).
2. Walk the zone graph: `lan → wan` requires a `forward` rule; check `allow`/`deny` lists in order.
3. Emit a structured trace:
   ```json
   {
     "verdict": "allow",
     "matched_rule": "zones.lan.forward.allow[2]",
     "rule_text": "tcp dport 443 accept",
     "nftables_chain": "forward_lan_wan",
     "nftables_handle": 42,
     "evaluated_at": "2025-..."
   }
   ```
4. With `--explain-nft`, additionally dump the *actual* nftables rule that implements the decision, so the user can verify the generator did what it claimed.

This dual view — *policy intent* and *kernel reality* — is the whole point. It catches generator bugs (policy says allow, nftables says drop) and drift (someone hand-edited nftables).

**`routerctl status` / `health` / `diagnostics`** should be a single binary with subcommands, emitting JSON by default and a human table with `--format=table`. Structure:

- `routerctl status` — one-shot snapshot: interfaces up/down, addresses, routes, DHCP lease count, DNS query rate, BGP peer state, VRRP state, CAKE qdisc stats. JSON schema versioned.
- `routerctl health` — exit-code-driven checks: `0` healthy, `1` degraded, `2` critical. Each check has an ID (`dhcp.pool.exhausted`, `bgp.peer.down`, `vrrp.split-brain`, `cake.backlog.high`). Designed for Prometheus textfile collector and for `systemd` `ExecCondition`.
- `routerctl diagnostics` — bundle generator: tarball with `status.json`, `health.json`, `nft list ruleset`, `ip -j addr`, `ip -j route`, `ethtool -S` per interface, last 500 journal lines per core unit. Redacts secrets. This is the "attach to bug report" command.

**Why not a web dashboard first:** the critique is right. A dashboard is a *consumer* of structured data; if the structured data doesn't exist, the dashboard is a liability. Build the JSON contract first, then a dashboard is a weekend project. Also: SSH + `jq` works on a 64MB router; a browser does not.

**Concrete steps:**
1. Define JSON schemas in `docs/schemas/` (JSON Schema draft 2020-12) for `status`, `health`, `firewall-explain`.
2. Extend `router-diag` into `routerctl` with the subcommand structure above; keep `router-diag` as a deprecated alias.
3. Emit `topology.json` at build time from the evaluated attrset — this is the input to `firewall explain`.
4. Add `routerctl health --format=prometheus` for node_exporter textfile integration.

`[satisfied]`

---

## Q4 — Core Decoupling & Failure Isolation

**The critique is correct and this is the highest-leverage architectural change.** The current profile-based split is insufficient because a crashing `ntopng` can still exhaust memory, saturate the disk with logs, or (worst case) trigger an OOM that kills `kea` or `unbound`.

**Three-tier model:**

1. **`router-core`** — must never depend on observability or applications. Contains: `systemd-networkd`, `nftables`, `kea`, `unbound`/`technitium`, `keepalived`, `bird`/`frr`, `clatd`/`tayga`, `cake`/`tc`. These run in the host systemd namespace, with `MemoryMin=` reservations and `OOMScoreAdjust=-900` so the kernel prefers to kill anything else first.

2. **`router-observability`** — `ulogd`, `ntopng`, `netdata`, `prometheus-node-exporter`, flow exporters. **Isolation strategy: systemd slices + resource limits, not containers, for the default case.** Rationale:
   - Containers/microVMs add a network namespace, which means the observability tool can't see the host's interfaces without `--network=host` — which defeats the isolation.
   - What we actually want is *resource* isolation, not *namespace* isolation. `systemd` slices with `MemoryMax=`, `CPUQuota=`, `IOWeight=`, and `Slice=router-observability.slice` achieve this.
   - For tools that genuinely need namespace isolation (untrusted exporters, third-party binaries), offer `router.observability.<tool>.isolation = "container"` as an opt-in that runs the tool in a `systemd-nspawn` container with `--network=host` and a read-only bind of `/proc/net`.
   - **MicroVMs are overkill** for a router. They cost 50–100MB RAM each and add boot complexity. Reserve them for the "I want to run untrusted third-party code" case, which is rare.

3. **`router-applications`** — `caddy`, `wireguard` admin tunnels, `tailscale`, remote admin. These *do* warrant namespace isolation because they're user-facing and often third-party. Default to `systemd-nspawn` containers with their own network namespace, routed through the core via a veth pair. This is the one place where the container tax is worth paying.

**Failure isolation guarantees to encode:**
- `router-observability.slice` has `MemoryMax=256M` by default; if it OOMs, core is untouched.
- `router-applications.slice` has `MemoryMax=512M` and `CPUQuota=50%`.
- Core units have `Restart=always`, `RestartSec=1`, and `StartLimitBurst=0` (never give up).
- Observability units have `Restart=on-failure` with backoff; if they crash-loop, they stay down and `routerctl health` reports `observability.degraded` — but core health stays green.

**Concrete steps:**
1. Define three slices in `modules/core/slices.nix` with the resource limits above.
2. Audit every module: tag it `core`, `observability`, or `application`; assert no `core` module imports an `observability` or `application` module.
3. Add `router.profile = "core" | "core+obs" | "full"` as the top-level switch; `core` must fit in 128MB RAM.
4. Add a CI test that boots a `core`-only VM and asserts `systemctl list-units --state=running` contains no observability units.

`[satisfied]`

---

## Q5 — Automated NixOS VM Integration Tests & Compatibility Matrix

**Test topology.** The critique's `client <--> router <--> wanSimulator` is the right shape. Concretely, in `tests/`:

```
tests/
  lib/
    mkTopology.nix        # shared VM builders
    wanSim.nix            # a VM that acts as upstream ISP: DHCP server, DNS, HTTP, BGP peer
  dhcp/
    basic.nix             # client gets lease, can ping router, can reach wanSim
    pool-exhaustion.nix   # N clients, N+1th gets NAK
    static-lease.nix      # MAC-matched client gets fixed IP
  firewall/
    zone-isolation.nix    # guest cannot reach lan; lan can reach guest
    port-forward.nix      # wanSim -> router:443 -> lan:8443
    stateful.nix          # established/related works, invalid dropped
  nat/
    masquerade.nix        # client -> wanSim, source is router WAN IP
    nat64.nix             # IPv6-only client reaches IPv4 wanSim via CLAT/DNS64
  ha/
    vrrp-failover.nix     # two routers, kill master, VIP moves, client traffic resumes <2s
    vrrp-split-brain.nix  # partition, assert no dual-master
  dns/
    unbound-forward.nix   # client resolves via router, upstream is wanSim
    technitium-block.nix  # blocked domain returns NXDOMAIN
  qos/
    cake-latency.nix      # saturate link, assert p99 latency < 10ms
  bgp/
    peer-up.nix           # router peers with wanSim, advertises LAN prefix
    peer-down.nix         # wanSim withdraws, router removes route
```

Each test is a `nixosTest` with `nodes.client`, `nodes.router`, `nodes.wanSim`. Use `testScript` with `client.wait_for_unit("network-online.target")` and `client.succeed("ping -c1 10.0.0.1")`. For timing-sensitive tests (HA failover, CAKE latency), use `client.wait_until_succeeds` with a timeout and assert on the *duration*.

**Critical addition the critique missed:** a **negative test** suite. Assert that invalid topologies *fail eval* — `nix-instantiate --eval` on a topology with overlapping prefixes must exit non-zero with a specific message. This is how you prevent assertion regressions.

**Compatibility matrix.** Initial axes:

| Axis | Values | Status |
|---|---|---|
| Arch | `x86_64-linux`, `aarch64-linux` | Both must pass full test suite |
| Platform | QEMU VM, bare metal | VM in CI; bare metal via `nixos-rebuild test` on reference hardware |
| NIC driver | `virtio_net`, `igb`, `igc`, `r8169`, `mlx5` | `virtio_net` in CI; others via hardware-in-loop runners |
| IP version | IPv4-only, IPv6-only, dual-stack | All three in CI |
| WAN type | DHCP, static, PPPoE, DS-Lite | DHCP + static in CI; PPPoE/DS-Lite manual |
| HA | single-node, VRRP pair | Both in CI |
| Profile | `core`, `core+obs`, `full` | All three in CI |

Publish as `docs/compatibility.md` with a CI badge per cell. Cells that are "manual" get a documented procedure and a known-good hardware list.

**Concrete steps:**
1. Land `tests/lib/mkTopology.nix` and the `dhcp/basic.nix` test as a proof of concept.
2. Add `checks.<system>.integration` to `flake.nix` so `nix flake check` runs the suite.
3. Add a `checks.<system>.eval-negative` suite for assertion tests.
4. Stand up a hardware-in-loop runner (a NUC + a managed switch + a second NUC as wanSim) for `igb`/`igc`/`r8169` validation.
5. Publish `docs/compatibility.md` with the matrix above.

`[satisfied-conditional: hardware-in-loop runner is provisioned for non-virtio NIC validation]`

---

## Q6 — Roadmap & Work Item Priorities

**Yes, support a feature freeze — with a hard boundary.** The critique is right that the project has crossed the threshold where *more features* actively reduce quality. 400 commits and 50+ modules without a full integration test suite is a liability, not an achievement. Freeze new feature modules for **two release cycles** (or ~90 days, whichever is longer), with a narrow exception process: a feature may land during freeze only if it is required to *test* or *assert* an existing feature.

**Immediate work items, in priority order:**

**P0 — Safety net (weeks 1–3):**
1. `lib/assertions.nix` with the ten assertions from Q2. Wire into `flake.nix` checks.
2. `tests/lib/mkTopology.nix` + `dhcp/basic.nix` + `firewall/zone-isolation.nix`. Prove the harness works.
3. `routerctl status` and `routerctl health` with JSON output. This is the observability primitive everything else builds on.
4. `docs/positioning.md` and README rewrite. Positioning is cheap and unblocks everything else.

**P1 — Isolation & diagnostics (weeks 4–8):**
5. Three-tier slice architecture from Q4. Audit every module's tier.
6. `routerctl firewall explain` with `topology.json` emission.
7. `routerctl diagnostics` bundle generator.
8. `lib/nic-capabilities.nix` + `router.optimizations.strict`.

**P2 — Test coverage & matrix (weeks 9–16):**
9. Full `tests/` suite from Q5: NAT, HA, DNS, QoS, BGP.
10. Negative eval test suite.
11. `docs/compatibility.md` with CI badges.
12. Hardware-in-loop runner for non-virtio NICs.

**P3 — Performance & polish (weeks 17–24):**
13. Benchmark suite: `iperf3` throughput, `flent`/`irtt` latency under load, CAKE effectiveness, XDP pps. Publish numbers in `docs/benchmarks.md`.
14. `routerctl hardware` four-state table.
15. Deprecation pass: remove legacy `networking.nat.*` usage, standardize on `networking.nftables.enable = true` and `systemd-networkd`.

**Explicitly deferred (post-freeze):**
- Web dashboard.
- New protocol support (OSPF, WireGuard mesh automation).
- Additional observability integrations.
- Anything that adds a module without a corresponding test.

**Concrete steps:**
1. Open a `FREEZE.md` at repo root with the freeze policy, exception process, and end date.
2. Create GitHub milestones P0–P3 with the items above; pin P0 to the next release.
3. Add a CI gate: any PR adding a new module without a test file fails.
4. Publish a monthly "freeze progress" note in `docs/`.

`[satisfied]`

---

## Summary

The critique is largely correct and technically sound. The two places it under-specifies are (a) the *isolation mechanism* for observability — slices, not containers, for the default case — and (b) the need for *negative* eval tests, not just positive integration tests. The two places it over-reaches are minor: "containerize peripheral observability" is too strong as a default, and "stop adding features" needs a narrow exception for test-enabling work. Everything else — rebranding, assertions, `routerctl`, three-tier decoupling, VM test topology, compatibility matrix, feature freeze — should be adopted essentially as written.

The single highest-leverage change is `lib/assertions.nix`. It converts an entire class of runtime failures into eval-time failures, costs nothing at runtime, and is the foundation on which the topology-typed positioning claim rests. Do that first.
```

---

### 2. Gemini CLI Voice (via `agy`)

```markdown
# Discussion 20: Architectural Critique Synthesis, Positioning, and Maturation Roadmap

**Scope:** `nix-router-optimized`  
**Round:** Multi-Agent Deliberation & External Critique Synthesis  
**Grounding Sources:**  
- [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix)
- [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix)
- [router-firewall.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-firewall.nix)
- [router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix)
- [router-networking.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-networking.nix)
- [router-ha.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-ha.nix)
- [router-observability.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-observability.nix)
- [router-diag.sh](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/pkgs/router-diag/router-diag.sh)
- [tests/README.md](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/tests/README.md)

---

### Executive Overview & Critique Audit

The external review highlights crucial inflection points as `nix-router-optimized` transitions from a rapid-prototyping phase (over 400 commits, 50+ modules, 93 work items) into a hardened production router distribution.

While parts of the external critique accurately diagnose our architectural debt (e.g., lack of QEMU VM tests, unconstrained hardware offload flags, and monorepo coupling of core vs. observability), other parts misunderstand our stack (e.g., presuming we use legacy `networking.nat.*` or scripted networking, when we are already 100% native `systemd-networkd` and pure `nftables`).

Below is the technical evaluation across all six discussion questions.

---

### Q1 (Positioning & Framework Identity)

#### 1. Technical Analysis
- **What the critique got right:**
  - Emphasizing *"RouterOS-like performance"* in our top-level identity ([flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix#L2) and [router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L1)) is a major positioning liability. MikroTik RouterOS is a proprietary network operating system featuring a vendor-specific fastpath packet engine. In our repo, "RouterOS-inspired" was historically used as shorthand for kernel conntrack tuning and flowtable offloading. In practice, it sounds like benchmark vanity and distracts from the core engineering value of the project.
  - The framework's true value proposition is: **typed network topology $\rightarrow$ derived nftables/networkd/DHCP/DNS configuration $\rightarrow$ deterministic edge deployment $\rightarrow$ verifiable performance**.
- **What the critique misunderstood:**
  - The critique framed the project as if it were simply a collection of kernel sysctl tweaks and performance scripts. In reality, the codebase contains sophisticated protocol engines—such as declarative 464XLAT/CLAT control planes ([router-clat.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-clat.nix)), VRRP HA with BGP neighbor promotion and WAN MAC cloning ([router-ha.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-ha.nix)), and Kea HA synchronization.
- **Exact Technical Differentiation against `chayleaf/nixos-router`:**
  1. **Stack Philosophy (`systemd-networkd` vs. Scripted Netns):**
     - `chayleaf/nixos-router` is built around network namespaces (`router.networkNamespaces`) and custom scripted networking wrapper commands, explicitly rejecting `systemd-networkd` due to historical limitations.
     - `nix-router-optimized` standardizes strictly on upstream declarative **`systemd-networkd`** ([router-networking.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-networking.nix)) and pure declarative **`nftables`** ([router-firewall.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-firewall.nix)), maintaining full alignment with mainstream NixOS evolution.
  2. **Abstraction Level (Complete Router Appliance vs. Low-Level NFT DSL):**
     - `chayleaf/nixos-router` expects operators to write raw nftables rules or use its `notnft` JSON DSL from scratch; it does not generate zone firewalls, MSS clamping, or NAT rules automatically.
     - `nix-router-optimized` provides a **declarative forward-only zone firewall** ([router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix)), automatic hairpin NAT, SYN proxying, bogon filtering, and RFC 8028 multi-homing.
  3. **Multi-Protocol Edge Services:**
     - `nix-router-optimized` includes first-class integrated modules for BGP (FRR), stateful Kea DHCP, Technitium/Unbound DNS with split-horizon overrides, CAKE SQM, and active-passive VRRP HA failover out-of-the-box.

#### 2. Concrete Technical Steps
1. Rebrand the project in [flake.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/flake.nix) and [README.md](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/README.md) to:
   > *"A typed, topology-driven declarative router framework for NixOS: Deterministic edge networking, zone security, and resilient protocol orchestration."*
2. Deprecate claims of "RouterOS emulation"; re-label [modules/router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix) to `router-kernel-tuning.nix`.

**Satisfaction:** `[satisfied]`

---

### Q2 (Safety, Assertions & Hardware Safety Boundaries)

#### 1. Technical Analysis
- **What the critique got right:**
  - **Dangerous Offload Blindness:** In [modules/router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L203-L209), the module executes:
    ```bash
    ethtool -K $iface gro on 2>/dev/null || true
    ethtool -K $iface lro on 2>/dev/null || true
    ```
    **Enabling LRO (Large Receive Offload) on a forwarding router is a critical networking violation.** In Linux, LRO aggregates TCP segments without preserving transport header checksums or packet boundaries, which silently breaks routing, corrupts forwarded TCP streams, and degrades NAT/conntrack. GRO is safe for routing; LRO is hostile to forwarding.
  - **Evaluation Gap:** Currently, assertions in [router-zones.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-zones.nix#L133-L164) only verify zone naming and interface uniqueness. There are no build-time assertions preventing overlapping subnets, DHCP pool misallocations, or MTU mismatches.
- **What the critique misunderstood:**
  - The critique implies that NIC hardware capabilities should be checked during Nix evaluation. However, Nix evaluation is hermetic and occurs on the build host, which has no access to the target machine's sysfs, PCI bus, or `ethtool` state. Hardware capability boundaries must be split into:
    1. **Evaluation-time logical invariants** (pure Nix).
72F 10D:

./ caddy-reverse-proxy.nix dns-blocklists.nix dns-zone.nix dns.nix monitoring.nix nftables-fasttrack.nix router-bgp.nix router-clat.nix router-cloudflare-tunnel.nix router-cloudflare-warp.nix router-dashboard.nix router-ddns.nix router-dhcp.nix router-dns-service.nix router-dns64.nix router-firewall.nix router-ha.nix router-headscale.nix router-homelab.nix router-kea.nix router-log-storage.nix router-mdns.nix router-mwan.nix router-nat64.nix router-ndp-proxy.nix router-netbird.nix router-network-security.nix router-networking.nix router-nptv6.nix router-ntopng.nix router-ntp.nix router-observability.nix router-openvpn.nix router-optimizations.nix router-pangolin.nix router-pppoe.nix router-remote-admin.nix router-rgbdns.nix router-security-hardened.nix router-sqm.nix router-tailscale.nix router-technitium.nix router-translation-backend-lib.nix router-tunnels.nix router-twingate.nix router-upnp.nix router-vpn.nix router-wireguard.nix router-zerotier.nix router-zones.nix
+22 more

ext: .nix(50) .py(8) .json(5) .html(3) .exs(2)

codex
The repository already contains a prior Discussion 20 synthesis, but I’m independently validating its strongest claims against the implementation—especially legacy NAT/networking usage, offload behavior, current assertions, diagnostics, and whether VM integration tests truly exist.
exec
/run/current-system/sw/bin/bash -lc "rtk rg -n \"networking\\.nat|networking\\.useNetworkd|systemd\\.network|networking\\.nftables|ethtool -K|lro|gro|gso|tso|assertions =|router-diag|make-test-python|nixosTest\" /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/tests /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/pkgs /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/flake.nix" in /home/deepwatrcreatur
 succeeded in 0ms:
424 matches in 62 files:

/.../roundtable-20/flake.nix:54:router-diag = pkgs.callPackage ./pkgs/router-diag { };
/.../modules/dns-blocklists.nix:150:assertions = [
/.../modules/dns-zone.nix:371:assertions = [
/.../modules/monitoring.nix:458:groups = [{
/.../modules/nftables-fasttrack.nix:56:assertions = [
/.../modules/nftables-fasttrack.nix:63:networking.nftables.enable = true;
/.../modules/nftables-fasttrack.nix:66:networking.nftables.ruleset = let
/.../modules/router-bgp.nix:413:assertions =
/.../modules/router-clat.nix:185:assertions = [
/.../modules/router-clat.nix:269:systemd.network.netdevs."30-${translationBackend.runtime.interfaceName}" = {
/.../modules/router-clat.nix:276:systemd.network.networks."30-${translationBackend.runtime.interfaceName}" = {
/.../router-clat/clat-dns.py:532:sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
/.../router-clat/clat-dns.py:599:"""Start the HTTP status server in a background thread."""
/.../modules/router-cloudflare-tunnel.nix:148:assertions =
/.../modules/router-dashboard.nix:937:group = "router-dashboard";
/.../modules/router-dashboard.nix:942:users.groups.router-dashboard = { };
/.../modules/router-dashboard.nix:1062:assertions = [
/.../api/server.py:2643:# Start speed test in background thread
/.../api/server.py:3132:return match.group(1)
/.../api/server.py:3165:prefix = prefix_match.group(1) if prefix_match else 'FW-LOG'
/.../api/server.py:3173:fields[key] = match.group(1)
/.../api/server.py:3190:'timestamp': timestamp_match.group(1) if timestamp_match else '',
/.../api/server.py:3278:sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
/.../api/server.py:3424:return match.group(1) if match else 'N/A'
/.../css/dashboard.css:43:background: var(--bg-primary);
/.../css/dashboard.css:51:background: var(--bg-primary);
/.../css/dashboard.css:62:background: var(--bg-sidebar);
/.../css/dashboard.css:84:background: #f5b068;
/.../css/dashboard.css:123:background: var(--bg-topbar);
/.../css/dashboard.css:137:background: var(--bg-search);
/.../css/dashboard.css:149:background: transparent;
/.../css/dashboard.css:212:background: #f5b068;
/.../css/dashboard.css:226:background: #ffc37a;
/.../css/dashboard.css:231:background: var(--bg-card);
/.../css/dashboard.css:269:background: transparent;
/.../css/dashboard.css:277:transition: background 0.2s ease, border-color 0.2s ease, color 0.2s ease;
/.../css/dashboard.css:282:background: rgba(56, 189, 248, 0.12);
/.../css/dashboard.css:288:background: var(--accent-button);
/.../css/dashboard.css:307:background: rgba(59, 130, 246, 0.08);
/.../css/dashboard.css:345:background: rgba(56, 189, 248, 0.12);
/.../css/dashboard.css:350:background: var(--bg-widget-solid);
/.../css/dashboard.css:386:background: rgba(15, 27, 46, 0.45);
/.../css/dashboard.css:419:background: rgba(16, 185, 129, 0.2);
/.../css/dashboard.css:425:background: rgba(239, 68, 68, 0.2);
/.../css/dashboard.css:431:background: rgba(245, 158, 11, 0.2);
/.../css/dashboard.css:441:background: var(--bg-input);
/.../css/dashboard.css:488:background: var(--bg-primary);
/.../css/dashboard.css:496:background: linear-gradient(90deg, var(--accent-blue), var(--accent-purple));
/.../css/dashboard.css:502:background: linear-gradient(90deg, var(--accent-green), #34d399);
  +165 more in /.../css/dashboard.css
/.../widgets/dhcp-widget.js:80:<span class="scope-count" style="margin-left: 6px; background: rgba(59, 130, ...
/.../widgets/dhcp-widget.js:85:<span class="scope-count" style="margin-left: 6px; background: rgba(239, 68, ...
/.../widgets/dns-widget.js:45:<div class="progress-fill" id="${this.id}-block-bar" style="background: #ef44...
/.../widgets/dns-widget.js:52:<div class="progress-fill" id="${this.id}-cache-bar" style="background: #10b9...
/.../widgets/gateway-widget.js:70:backgroundColor: 'rgba(15, 23, 42, 0.9)',
/.../widgets/gateway-widget.js:163:backgroundColor: 'transparent',
/.../widgets/interface-widget.js:72:backgroundColor: 'rgba(16, 185, 129, 0.2)',
/.../widgets/interface-widget.js:81:backgroundColor: 'rgba(59, 130, 246, 0.2)',
/.../widgets/inventory-widget.js:227:.filter(group => this.groupMatches(group));
/.../widgets/inventory-widget.js:251:subnetsEl.innerHTML = visibleGroups.map(group => this.renderSubnetGroup(group...
/.../widgets/inventory-widget.js:253:const visibleHostIds = visibleGroups.flatMap(group => group.hosts.map(host =>...
/.../widgets/inventory-widget.js:276:groupMatches(group) {
/.../widgets/inventory-widget.js:280:group.subnet.label,
/.../widgets/inventory-widget.js:281:group.subnet.cidr,
/.../widgets/inventory-widget.js:282:group.subnet.gatewayAddress,
/.../widgets/inventory-widget.js:283:group.subnet.dhcpBackend || ''
/.../widgets/inventory-widget.js:286:const hostMatches = group.hosts.some(host => this.hostMatchesFilters(host));
/.../widgets/inventory-widget.js:317:renderSubnetGroup(group) {
/.../widgets/inventory-widget.js:318:const { subnet, hosts } = group;
/.../widgets/inventory-widget.js:774:const grouped = this.groupEdgesByKind(visible);
/.../widgets/inventory-widget.js:775:listEl.innerHTML = grouped.map(group => `
/.../widgets/inventory-widget.js:779:<div class="inventory-subnet-name">${this.escape(group.label)}</div>
/.../widgets/inventory-widget.js:780:<div class="inventory-subnet-meta">${group.edges.length} relationship${group....
/.../widgets/inventory-widget.js:784:${group.edges.map(edge => this.renderEdgeRow(edge)).join('')}
/.../widgets/inventory-widget.js:799:groupEdgesByKind(edges) {
/.../widgets/inventory-widget.js:806:const groups = {};
/.../widgets/inventory-widget.js:809:(groups[kind] = groups[kind] || []).push(edge);
/.../widgets/inventory-widget.js:812:return order.filter(kind => groups[kind]?.length > 0).map(kind => ({
/.../widgets/inventory-widget.js:815:edges: groups[kind]
/.../widgets/traffic-widget.js:72:backgroundColor: 'rgba(16, 185, 129, 0.1)',
/.../widgets/traffic-widget.js:82:backgroundColor: 'rgba(59, 130, 246, 0.1)',
/.../widgets/traffic-widget.js:117:backgroundColor: 'rgba(15, 23, 42, 0.9)',
/.../widgets/tunnels-widget.js:3:* Displays application tunnel status (zrok/ngrok/other).
/.../widgets/tunnels-widget.js:93:<p>Define services.router-tunnels.tunnels entries (e.g., zrok, ngrok, or Clou...
/.../modules/router-ddns.nix:27:${pkgs.coreutils}/bin/chown root:${escapeShellArg config.services.inadyn.grou...
/.../modules/router-ddns.nix:117:assertions = [
/.../modules/router-dhcp.nix:249:assertions =
/.../modules/router-dhcp.nix:264:systemd.network.networks = mapAttrs' (
/.../modules/router-dns-service.nix:178:assertions = [
/.../modules/router-dns64.nix:27:assertions = [
/.../modules/router-firewall.nix:479:group = mkOption {
/.../modules/router-firewall.nix:482:description = "NFLOG group ID for flow logging.";
/.../modules/router-firewall.nix:494:assertions = [
/.../modules/router-firewall.nix:513:networking.nftables.enable = true;
/.../modules/router-firewall.nix:516:networking.nftables.ruleset = ''
/.../modules/router-firewall.nix:533:log group ${toString cfg.flowLogging.group}
/.../modules/router-headscale.nix:146:assertions = [
/.../modules/router-kea.nix:342:description = "Name of this Kea server in the HA group.";
/.../modules/router-kea.nix:346:description = "Role of this server in the HA group.";
/.../modules/router-kea.nix:436:assertions = [
/.../modules/router-log-storage.nix:15:group = "root";
/.../modules/router-log-storage.nix:22:group = "root";
/.../modules/router-log-storage.nix:27:map (dir: "d ${cfg.mountPoint}/${dir.name} ${dir.mode} ${dir.user} ${dir.grou...
/.../modules/router-log-storage.nix:33:chown ${dir.user}:${dir.group} ${cfg.mountPoint}/${dir.name}
/.../modules/router-log-storage.nix:56:group = mkOption {
/.../modules/router-log-storage.nix:59:description = "Owner group for the directory.";
/.../modules/router-mwan.nix:148:assertions = [
/.../modules/router-nat64.nix:73:assertions = [
/.../modules/router-ndp-proxy.nix:164:assertions = [
/.../modules/router-netbird.nix:150:assertions = [
/.../modules/router-network-security.nix:143:install -d -m 0755 -o ${config.services.suricata.settings.run-as.user} -g ${c...
/.../modules/router-network-security.nix:144:install -d -m 0755 -o ${config.services.suricata.settings.run-as.user} -g ${c...
/.../modules/router-network-security.nix:148:install -m 0644 -o ${config.services.suricata.settings.run-as.user} -g ${conf...
/.../modules/router-network-security.nix:156:install -m 0644 -o ${config.services.suricata.settings.run-as.user} -g ${conf...
/.../modules/router-network-security.nix:164:chown ${config.services.suricata.settings.run-as.user}:${config.services.suri...
/.../modules/router-network-security.nix:403:assertions = [
/.../modules/router-network-security.nix:429:vars.address-groups.HOME_NET = suricataHomeNet;
/.../modules/router-network-security.nix:430:vars.address-groups.EXTERNAL_NET = "any";
/.../modules/router-network-security.nix:449:users.groups.snort = mkIf cfg.snort.enable { };
/.../modules/router-network-security.nix:452:group = "snort";
/.../modules/router-network-security.nix:455:users.groups.zeek = mkIf cfg.zeek.enable { };
/.../modules/router-network-security.nix:458:group = "zeek";
/.../modules/router-network-security.nix:461:users.groups.evebox = mkIf cfg.suricata.evebox.enable { };
/.../modules/router-network-security.nix:464:group = "evebox";
/.../modules/router-networking.nix:622:assertions =
/.../modules/router-networking.nix:642:networking.useNetworkd = mkIf cfg.useNetworkd true;
/.../modules/router-networking.nix:644:systemd.network.enable = mkIf cfg.useNetworkd true;
/.../modules/router-networking.nix:645:systemd.network.wait-online.enable = cfg.waitOnline;
/.../modules/router-networking.nix:647:systemd.network.netdevs =
/.../modules/router-networking.nix:652:systemd.network.networks =
/.../modules/router-nptv6.nix:131:assertions = [
/.../modules/router-nptv6.nix:138:networking.nftables.enable = true;
/.../modules/router-nptv6.nix:139:networking.nftables.ruleset = mkIf (!config.services.router-firewall.enable o...
/.../modules/router-observability.nix:27:description = "Netfilter NFLOG group for ulogd.";
/.../modules/router-observability.nix:71:group = cfg.ulogdGroup;
/.../modules/router-openvpn.nix:137:assertions = [
/.../modules/router-optimizations.nix:72:description = "The router-diag package to install.";
/.../modules/router-optimizations.nix:77:assertions = [
/.../modules/router-optimizations.nix:203:${pkgs.ethtool}/bin/ethtool -K $iface tso on 2>/dev/null || true
/.../modules/router-optimizations.nix:204:${pkgs.ethtool}/bin/ethtool -K $iface gso on 2>/dev/null || true
/.../modules/router-optimizations.nix:205:${pkgs.ethtool}/bin/ethtool -K $iface gro on 2>/dev/null || true
/.../modules/router-optimizations.nix:206:${pkgs.ethtool}/bin/ethtool -K $iface lro on 2>/dev/null || true
/.../modules/router-optimizations.nix:207:${pkgs.ethtool}/bin/ethtool -K $iface sg on 2>/dev/null || true
/.../modules/router-optimizations.nix:208:${pkgs.ethtool}/bin/ethtool -K $iface tx on 2>/dev/null || true
/.../modules/router-optimizations.nix:209:${pkgs.ethtool}/bin/ethtool -K $iface rx on 2>/dev/null || true
/.../modules/router-security-hardened.nix:173:assertions = [
/.../modules/router-security-hardened.nix:267:assertions = [
/.../modules/router-security-hardened.nix:317:assertions = [
/.../modules/router-technitium.nix:1208:assertions = [
/.../modules/router-tunnels.nix:16:type = types.enum [ "zrok" "ngrok" "cloudflare" "other" ];
/.../modules/router-tunnels.nix:17:description = "Tunnel provider backing this entry (zrok, ngrok, Cloudflare, e...
/.../modules/router-tunnels.nix:41:enable = mkEnableOption "metadata for application tunnels (zrok/ngrok/other) ...
/.../modules/router-vpn.nix:60:systemd.network.netdevs = mapAttrs' (name: iface: nameValuePair "30-${iface.d...
/.../modules/router-vpn.nix:76:systemd.network.networks = mapAttrs' (name: iface: nameValuePair "30-${iface....
/.../modules/router-wireguard.nix:140:assertions = [
/.../modules/router-zerotier.nix:117:assertions = [
/.../modules/router-zones.nix:133:assertions =
/.../router-diag/default.nix:4:name = "router-diag";
/.../router-diag/default.nix:15:text = builtins.readFile ./router-diag.sh;
/.../router-diag/router-diag.sh:4:# router-diag: Operational Diagnostics CLI for NixOS Router
/.../router-diag/router-diag.sh:14:echo "Usage: router-diag <command> [subcommand]"
/.../tests/README.md:8:until the repo intentionally grows a runtime test matrix.
/.../tests/default.nix:115:assertions = [
/.../tests/doc-examples.nix:136:assertion = config.systemd.network.networks."10-router-wan-primary".matchConf...
/.../tests/doc-examples.nix:140:assertion = config.systemd.network.networks."20-router-lan".matchConfig.Name ...
/.../tests/doc-examples.nix:144:assertion = config.systemd.network.networks."20-router-lan".networkConfig.DHC...
/.../tests/doc-examples.nix:152:assertion = lib.hasInfix ''iifname {"lan0"} oifname {"wan0"} accept'' config....
/.../tests/doc-examples.nix:161:assertion = config.systemd.network.networks."10-router-wan-primary".matchConf...
/.../tests/doc-examples.nix:165:assertion = config.systemd.network.networks."20-router-lan".matchConfig.Name ...
/.../tests/doc-examples.nix:173:assertion = lib.hasInfix ''iifname {"ens16"} oifname {"ens17"} accept'' confi...
/.../tests/doc-examples.nix:223:assertion = config.systemd.network.networks."20-router-lan".networkConfig.DHC...
/.../tests/doc-examples.nix:253:assertion = config.systemd.network.networks."20-router-lan".dhcpServerConfig....
/.../tests/doc-examples.nix:257:assertion = config.systemd.network.networks."20-router-lan".dhcpServerConfig....
/.../tests/doc-examples.nix:302:assertion = lib.hasInfix ''iifname { "eth1" } jump zone_lan_forward'' config....
/.../tests/doc-examples.nix:306:assertion = lib.hasInfix ''oifname { "eth0" } accept comment "router-zones la...
/.../tests/doc-examples.nix:310:assertion = lib.hasInfix ''oifname { "eth1" } drop comment "router-zones iot-...
/.../tests/doc-examples.nix:314:assertion = lib.hasInfix ''return comment "router-zones default for lan"'' co...
/.../tests/doc-examples.nix:318:assertion = !(lib.hasInfix "zone_lan_input" config.networking.nftables.ruleset);
/.../tests/doc-examples.nix:420:assertion = lib.hasInfix "tcp option maxseg size set rt mtu" config.networkin...
/.../tests/doc-examples.nix:424:assertion = lib.hasInfix ''ip daddr { 192.168.1.0/24 } masquerade'' config.ne...
/.../tests/doc-examples.nix:674:lib.hasInfix ''iifname "tailscale0"'' config.networking.nftables.ruleset
/.../tests/doc-examples.nix:675:&& lib.hasInfix ''iifname "nb-router"'' config.networking.nftables.ruleset;
/.../tests/doc-examples.nix:748:assertion = lib.hasInfix "jump geoip_block" config.networking.nftables.ruleset;
/.../tests/doc-examples.nix:752:assertion = lib.hasInfix "iifname {\"eth0\"} ip saddr @blocked_countries drop...
/.../tests/doc-examples.nix:756:assertion = lib.hasInfix "oifname {\"eth0\"} ip daddr @wan_egress_bogon_ipv4 ...
/.../tests/doc-examples.nix:760:assertion = lib.hasInfix "iifname \"eth1\" ether saddr != @allowed_macs_eth1 ...
/.../tests/doc-examples.nix:776:assertion = lib.hasInfix "counter accept" config.networking.nftables.ruleset;
/.../tests/doc-examples.nix:780:assertion = lib.hasInfix "counter drop" config.networking.nftables.ruleset;
  +5 more in /.../tests/doc-examples.nix
/.../tests/interface-firewall-invariants.nix:50:assertion = lib.hasInfix ''iifname {"br-lan"} oifname {"eth-wan"} accept'' co...
/.../tests/interface-firewall-invariants.nix:54:assertion = lib.hasInfix ''iifname {"mgmt0"} oifname {"eth-wan"} accept'' con...
/.../tests/interface-firewall-invariants.nix:58:assertion = lib.hasInfix ''iifname {"eth-wan"} jump WAN_LOCAL'' config.networ...
/.../tests/interface-firewall-invariants.nix:75:assertion = !(lib.hasInfix "iifname  " config.networking.nftables.ruleset);
/.../tests/interface-firewall-invariants.nix:79:assertion = !(lib.hasInfix "oifname  " config.networking.nftables.ruleset);
/.../tests/router-clat-observability.nix:29:assertions = [
/.../tests/router-clat-observability.nix:62:assertions = [
/.../tests/router-dashboard-firewall.nix:19:assertions = [
/.../tests/router-dashboard-inventory.nix:56:assertions = [
/.../tests/router-dashboard-inventory.nix:155:assertions = [
/.../tests/router-dashboard-inventory.nix:184:assertions = [
/.../tests/router-dashboard-inventory.nix:283:assertions = [
/.../tests/router-dashboard-service-control.nix:26:assertions = [
  +1 more in /.../tests/router-dashboard-service-control.nix
+8 more files

codex
One important correction is emerging: evaluation can validate declared intent and a declared hardware profile, but it cannot probe the target NIC. “Supported” must therefore be either user-declared/board-profile-derived or discovered at activation time; treating a static driver table as authoritative would create false confidence. I’m also verifying the comparison project from its primary repository before stating differentiation.
web search: 
web search: site:github.com/chayleaf/nixos-router chayleaf nixos-router README network namespaces nftables
exec
/run/current-system/sw/bin/bash -lc "rtk sed -n '1,130p' /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/tests/README.md && rtk sed -n '1,180p' /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/pkgs/router-diag/router-diag.sh && rtk sed -n '1,260p' /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-optimizations.nix && rtk sed -n '1,210p' /home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-sqm.nix" in /home/deepwatrcreatur
 succeeded in 0ms:
# Router Flake Checks

This directory contains fast evaluation-oriented checks for the flake. Add new
checks here when a module needs a minimal NixOS configuration, option assertion,
or other guardrail that should run in CI.

Prefer cheap checks that evaluate module configuration. Do not add VM tests here
until the repo intentionally grows a runtime test matrix.

## Pattern

Use `mkNixosEvalCheck` from `nixos-eval.nix` for module smoke tests:

```nix
mkNixosEvalCheck "router-example" [
  self.nixosModules.router-example
  {
    services.router-example.enable = true;
  }
]
```

The helper evaluates `config.system.build.toplevel` and returns a small
derivation. This keeps checks CI-visible without forcing a full system closure
build.
#!/usr/bin/env bash
set -euo pipefail

# router-diag: Operational Diagnostics CLI for NixOS Router
# VyOS-inspired "show" commands for terminal-based debugging

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_usage() {
    echo "Usage: router-diag <command> [subcommand]"
    echo ""
    echo "Commands:"
    echo "  show interfaces    Display interface status and IP addresses"
    echo "  show firewall      Summary of active nftables chains and hits"
    echo "  show vpn           WireGuard and Tailscale status"
    echo "  show health        Explicit health check results"
    echo "  help               Display this help message"
}

function show_interfaces() {
    echo -e "${YELLOW}--- Interface Status ---${NC}"
    ip -4 -brief addr show
    echo ""
    echo -e "${YELLOW}--- Carrier Status ---${NC}"
    for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
        if [ "$iface" != "lo" ]; then
            state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
            echo -n "  $iface: "
            if [ "$state" == "up" ]; then
                echo -e "${GREEN}$state${NC}"
            else
                echo -e "${RED}$state${NC}"
            fi
        fi
    done
}

function show_firewall() {
    echo -e "${YELLOW}--- Firewall Summary (nftables) ---${NC}"
    if command -v nft >/dev/null; then
        echo "Active tables:"
        nft list tables
        echo ""
        echo "Ruleset statistics (non-zero counters):"
        nft list ruleset | grep -E "counter packets [1-9]" || echo "No active counters found."
    else
        echo -e "${RED}Error: nft command not found.${NC}"
    fi
}

function show_vpn() {
    echo -e "${YELLOW}--- VPN Status (WireGuard) ---${NC}"
    if command -v wg >/dev/null; then
        sudo wg show || echo "No active WireGuard interfaces."
    else
        echo "wg command not found."
    fi
    echo ""
    echo -e "${YELLOW}--- VPN Status (Tailscale) ---${NC}"
    if command -v tailscale >/dev/null; then
        tailscale status || echo "Tailscale not running."
    else
        echo "tailscale command not found."
    fi
}

function show_health() {
    echo -e "${YELLOW}--- Router Health Checks ---${NC}"
    # Derived from Task 05 health check services
    services=(
        "health-mgmt-ip"
        "health-lan-ip"
        "health-wan-carrier"
        "health-wan-ip"
    )
    
    for svc in "${services[@]}"; do
        echo -n "  $svc: "
        if systemctl is-active --quiet "$svc"; then
            echo -e "${GREEN}PASS${NC}"
        else
            echo -e "${RED}FAIL${NC}"
            systemctl status "$svc" --no-pager | grep -E "Active:|Main PID:" | sed 's/^/    /'
        fi
    done
}

# Main entry point
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

case "$1" in
    show)
        if [ $# -lt 2 ]; then
            show_usage
            exit 1
        fi
        case "$2" in
            interfaces) show_interfaces ;;
            firewall)   show_firewall ;;
            vpn)        show_vpn ;;
            health)     show_health ;;
            *)          show_usage; exit 1 ;;
        esac
        ;;
    help)
        show_usage
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
# Router performance optimizations inspired by RouterOS
# Includes fasttrack, hardware offload, queue management
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-optimizations;
in {
  options.services.router-optimizations = {
    enable = mkEnableOption "router performance optimizations";
    
    interfaces = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          device = mkOption {
            type = types.str;
            description = "Physical device name (e.g., ens18, eth0)";
          };
          
          role = mkOption {
            type = types.enum [ "wan" "lan" "opt" "management" ];
            default = "opt";
            description = "Interface role (wan, lan, opt, management)";
          };
          
          label = mkOption {
            type = types.str;
            description = "Human-readable label for dashboard (e.g., 'WAN', 'LAN', 'OPT1', 'Management')";
          };
          
          bandwidth = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Bandwidth limit for CAKE QoS (e.g., '100Mbit', '1Gbit'). Only applies to WAN interfaces.";
          };
        };
      });
      default = {};
      description = ''
        Interface configurations. Each interface can have an arbitrary label.
        Example:
        {
          wan = { device = "ens17"; role = "wan"; label = "WAN"; bandwidth = "1Gbit"; };
          lan = { device = "ens16"; role = "lan"; label = "LAN"; };
          mgmt = { device = "ens18"; role = "management"; label = "Management"; };
          opt1 = { device = "ens19"; role = "opt"; label = "OPT1"; };
        }
      '';
    };
    
    conntrack-max = mkOption {
      type = types.int;
      default = 262144;
      description = "Maximum number of connection tracking entries";
    };

    conntrack-hashsize = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = ''
        Hash table size for the conntrack module. Defaults to conntrack-max / 4.
        Larger values reduce hash chain length and improve lookup performance at
        the cost of memory (~8 bytes per bucket). Set via the nf_conntrack kernel
        module parameter, which must be configured before the module loads.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.hello; # Placeholder, should be overridden in flake or host
      description = "The router-diag package to install.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.conntrack-hashsize == null || cfg.conntrack-hashsize <= cfg.conntrack-max;
        message = "router-optimizations.conntrack-hashsize must not exceed conntrack-max (${toString cfg.conntrack-max}).";
      }
    ];

    # Set conntrack hash table size via module parameter (must be set before module loads)
    boot.extraModprobeConfig = let
      hashsize = if cfg.conntrack-hashsize != null then cfg.conntrack-hashsize else cfg.conntrack-max / 4;
    in "options nf_conntrack hashsize=${toString hashsize}";

    # Kernel modules for advanced networking
    boot.kernelModules = [ 
      "tcp_bbr"           # Better congestion control
      "sch_fq"            # Fair queue scheduler
      "sch_fq_codel"      # FQ-CoDel queue discipline
      "sch_cake"          # CAKE queue discipline
      "act_bpf"           # BPF actions
      "cls_bpf"           # BPF classifier
      "ifb"               # Intermediate functional block (for ingress shaping)
    ];

    # Advanced kernel network tuning
    boot.kernel.sysctl = {
      # IP forwarding
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      
      # Connection tracking optimizations (fasttrack-like)
      "net.netfilter.nf_conntrack_max" = cfg.conntrack-max;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 7200;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 30;
      "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 15;
      "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 30;
      
      # TCP optimizations
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_rmem" = "4096 87380 33554432";
      "net.ipv4.tcp_wmem" = "4096 87380 33554432";
      "net.ipv4.tcp_max_syn_backlog" = 8192;
      "net.ipv4.tcp_tw_reuse" = 1;
      
      # Core socket buffer sizes
      "net.core.rmem_default" = 262144;
      "net.core.rmem_max" = 33554432;
      "net.core.wmem_default" = 262144;
      "net.core.wmem_max" = 33554432;
      "net.core.netdev_max_backlog" = 5000;
      "net.core.optmem_max" = 65536;
      
      # Reduce TIME_WAIT buckets
      "net.ipv4.tcp_max_tw_buckets" = 200000;
      
      # Enable TCP window scaling
      "net.ipv4.tcp_window_scaling" = 1;
      
      # Enable selective acknowledgements
      "net.ipv4.tcp_sack" = 1;
      
      # Increase the maximum amount of memory allocated to shm
      "kernel.shmmax" = 68719476736;
      "kernel.shmall" = 4294967296;
      
      # Disable packet filtering on bridges (if used)
      "net.bridge.bridge-nf-call-iptables" = mkDefault 0;
      "net.bridge.bridge-nf-call-ip6tables" = mkDefault 0;
      "net.bridge.bridge-nf-call-arptables" = mkDefault 0;
      
      # Increase local port range
      "net.ipv4.ip_local_port_range" = "10000 65535";
      
      # Enable ECN (Explicit Congestion Notification)
      "net.ipv4.tcp_ecn" = 1;
      
      # Protect against time-wait assassination
      "net.ipv4.tcp_rfc1337" = 1;
    };

    # Install performance monitoring and traffic control tools
    environment.systemPackages = with pkgs; [
      ethtool              # Hardware offload configuration
      iproute2             # tc (traffic control) for queue management
      tcpdump              # Packet analysis
      conntrack-tools      # Connection tracking utilities
      iperf3               # Network performance testing
      mtr                  # Network diagnostics
      bpftools             # BPF/XDP tools
      bpftrace             # Dynamic tracing
      numactl              # NUMA control
      irqbalance           # IRQ balancing for multi-core
      cfg.package          # Operational diagnostics CLI
    ];

    # Enable IRQ balancing for better multi-core performance
    services.irqbalance.enable = true;

    # Systemd service to enable hardware offloads and queue management
    systemd.services.router-hardware-offload = {
      description = "Enable hardware offloads and queue management for router";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Function to configure interface
        configure_interface() {
          local iface=$1
          local role=$2
          local bandwidth=$3
          
          # Check if interface exists
          if ! ${pkgs.iproute2}/bin/ip link show $iface &>/dev/null; then
            echo "Interface $iface not found, skipping..."
            return
          fi
          
          # Enable hardware offloads
          ${pkgs.ethtool}/bin/ethtool -K $iface tso on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface gso on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface gro on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface lro on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface sg on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface tx on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface rx on 2>/dev/null || true
          
          # Increase ring buffer sizes for better performance
          ${pkgs.ethtool}/bin/ethtool -G $iface rx 4096 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -G $iface tx 4096 2>/dev/null || true
          
          # Enable interrupt coalescing
          ${pkgs.ethtool}/bin/ethtool -C $iface adaptive-rx on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -C $iface adaptive-tx on 2>/dev/null || true
          
          # Configure queue discipline
          if [ "$role" = "wan" ] && [ -n "$bandwidth" ]; then
            # WAN interface: use CAKE for better bufferbloat control
            ${pkgs.iproute2}/bin/tc qdisc replace dev $iface root cake bandwidth $bandwidth
          else
            # Non-WAN interfaces: use fq_codel for internal traffic
            ${pkgs.iproute2}/bin/tc qdisc replace dev $iface root fq_codel
          fi
          
          echo "Configured $iface (Role: $role)"
        }
        
        ${concatStringsSep "\n" (mapAttrsToList (name: iface: ''
          configure_interface ${iface.device} ${iface.role} ${if iface.bandwidth != null then iface.bandwidth else ""}
        '') cfg.interfaces)}
        
        echo "Router hardware offload configuration complete"
      '';
    };

  };
}
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-sqm;

  sqmInterfaceModule = types.submodule {
    options = {
      device = mkOption {
        type = types.str;
        description = "Interface device name (e.g., eth0).";
      };

      bandwidthIngress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "100mbit";
        description = "Ingress (download) bandwidth limit. Set to ~95% of your actual line speed.";
      };

      bandwidthEgress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "20mbit";
        description = "Egress (upload) bandwidth limit. Set to ~95% of your actual line speed.";
      };

      cakeArgs = mkOption {
        type = types.str;
        default = "nat triple-isolate rtt 100ms";
        description = "Extra arguments for the CAKE qdisc. 'nat' is usually required for routers.";
      };
    };
  };
in
{
  options.services.router-sqm = {
    enable = mkEnableOption "Smart Queue Management (SQM) with CAKE";

    interfaces = mkOption {
      type = types.listOf sqmInterfaceModule;
      default = [ ];
      description = "List of interfaces to apply SQM/CAKE queuing to.";
    };
  };

  config = mkIf cfg.enable {
    # We use a systemd service to apply the tc commands because networkd
    # qdisc support is limited/static and CAKE is often best applied via tc.
    systemd.services.apply-sqm = {
      description = "Apply SQM/CAKE traffic shaping";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = concatMapStringsSep "\n" (iface: ''
        echo "Applying SQM to ${iface.device}..."
        # Clear existing qdiscs
        ${pkgs.iproute2}/bin/tc qdisc del dev ${iface.device} root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev ${iface.device} ingress 2>/dev/null || true

        # Egress (root)
        ${if iface.bandwidthEgress != null then ''
          ${pkgs.iproute2}/bin/tc qdisc add dev ${iface.device} root handle 1: cake bandwidth ${iface.bandwidthEgress} ${iface.cakeArgs}
        '' else ''
          ${pkgs.iproute2}/bin/tc qdisc add dev ${iface.device} root handle 1: cake ${iface.cakeArgs}
        ''}

        # Ingress (using ifb for proper shaping if needed, but modern CAKE on ingress is also possible)
        # For simplicity in this first version, we apply CAKE to root.
        # Note: True ingress shaping usually requires an IFB device. 
        # For now, we focus on Egress which is where Bufferbloat is most severe.
      '') cfg.interfaces;
    };
  };
}

codex
## Q1 — Positioning and framework identity

Yes, retire “RouterOS-inspired performance” as the primary identity. It describes the historical motivation of [router-optimizations.nix](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-optimizations.nix), but it invites comparisons with MikroTik’s appliance ecosystem, proprietary fast paths, hardware acceleration, and management interface—none of which define this project.

The stronger identity is:

> A topology-driven NixOS router framework that derives network policy and services, produces reproducible deployments, and verifies their safety and performance.

However, “typed topology → derived firewall/DHCP/DNS” is presently more roadmap than fully realized fact. The repository has typed NixOS options and substantial module-local assertions, but topology is distributed across networking, zones, DHCP, DNS, HA, and optimization modules. Rebranding should therefore coincide with introducing a canonical normalized topology representation; otherwise the claim will outrun the implementation.

The critique also misunderstands two current properties:

- The project already uses `systemd-networkd` through [router-networking.nix](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-networking.nix:642).
- Firewall and NAT policy are already expressed through native nftables modules, including [router-firewall.nix](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-firewall.nix:513). A migration away from `networking.nat.*` is not a meaningful major work item because repository modules do not currently use it.

The defensible differentiation from `chayleaf/nixos-router` is architectural, not “more features therefore better”:

- `chayleaf/nixos-router` emphasizes flexible network namespaces, its own scripted networking lifecycle, interface-level service composition, and typed JSON nftables via `notnft`.
- This project emphasizes upstream `systemd-networkd`, generated zone policy, integrated edge services, HA, translation mechanisms, and operational profiles.
- `chayleaf/nixos-router` currently expects operators to define much of their nftables policy themselves, while this project derives significant policy from higher-level roles and zones. These characteristics are documented in the project’s [primary repository](https://github.com/chayleaf/nixos-router).
- The future differentiator should be a single normalized topology feeding multiple generators and validations. Until that exists, describe the project as “topology-oriented,” not as already possessing a complete topology compiler.

Concrete work:

1. Replace RouterOS language in the README and flake description, retaining it only as historical context.
2. Define a versioned `router.topology` model and normalize legacy module options into it.
3. Document which outputs are genuinely derived from topology today.
4. Publish a factual comparison covering networking lifecycle, namespace model, policy abstraction, DHCP/DNS, HA, testing, and compatibility—not subjective claims such as “gives you a network.”

`[satisfied-conditional: the positioning change is paired with a canonical topology model and does not overstate current derivation]`

## Q2 — Assertions and hardware safety boundaries

The critique correctly prioritizes topology assertions, but it understates the assertions already present throughout the repository. Zones, firewall, DHCP, Kea, BGP, CLAT, DNS, and other modules already contain local checks. The immediate need is to make cross-module invariants centralized and testable, not to imply that validation is absent.

Highest-priority invariants:

1. Every firewall, DHCP, DNS, HA, VPN, and routing zone reference resolves to a declared object.
2. Routed IPv4 and IPv6 prefixes do not overlap unless an explicit overlap/VRF exception exists.
3. DHCP pools are contained in their subnet, do not include the gateway, VIP, broadcast/network address, or reservations, and do not overlap.
4. Static addresses, reservations, and MAC/client identifiers are unique in the appropriate scope.
5. Each interface has one routed ownership role; bridge members are not independently assigned routed addresses.
6. VLAN IDs are unique per parent, and parent references exist.
7. VRRP virtual-router IDs and VIPs are unique on a broadcast domain; VIPs do not collide with node addresses or pools.
8. MTU decreases along encapsulation paths and accounts for PPPoE, VLAN, CLAT/NAT64, WireGuard, and other overhead.
9. DNS64 is paired with a reachable NAT64 prefix/backend, and translation prefixes do not collide with routed space.
10. Port forwards have valid destinations and do not conflict on `(family, address, protocol, port)`.
11. HA-owned services and addresses have exactly one ownership mechanism.
12. CAKE bandwidth values are positive and shaping is attached only to declared interfaces.

Use a reusable topology-validation library, but keep assertions close enough to option definitions to produce precise paths such as `router.topology.zones.guest.ipv4.prefix`. Add negative evaluation fixtures for every invariant.

Hardware capability cannot be discovered during hermetic Nix evaluation. The safe state model is therefore:

- `requested`: operator intent.
- `declaredSupported`: knowledge from an explicit board/NIC profile, if one was selected.
- `runtimeAvailable`: what `ethtool`, sysfs, qdisc discovery, driver identity, and kernel facilities report.
- `effective`: post-application verification.
- `reason`: why requested state was not achieved or was suppressed.

A driver table may supply cautious defaults, but must not be authoritative: driver, firmware, kernel, virtualization, NIC revision, and device configuration all affect capabilities.

The current blanket activation in [router-optimizations.nix](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/modules/router-optimizations.nix:203) silently attempts TSO, GSO, GRO, LRO, ring resizing, and interrupt coalescing with `|| true`. That should be removed. In particular, LRO should default off on forwarding interfaces. CAKE must be coordinated with segmentation offloads and verified using `tc -j qdisc`, while XDP must distinguish generic, native, and offloaded modes.

Strict mode should fail activation—not evaluation—when runtime capability contradicts an explicit requirement. Best-effort mode should leave the router operational and report degradation.

`[satisfied]`

## Q3 — Firewall explainability and CLI diagnostics

Build on `router-diag`, but do not merely enlarge its shell script. The existing [router-diag.sh](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/pkgs/router-diag/router-diag.sh) is a useful low-dependency recovery tool, but it currently produces human-oriented summaries using `ip`, `nft`, `grep`, and `systemctl`. Preserve it as the degraded-mode fallback.

The new architecture should have three layers:

1. A pure policy evaluator consumes the normalized topology and answers hypothetical flows.
2. Firewall generation emits stable semantic rule IDs into nftables comments, such as `nr:forward:lan:wan:https`.
3. A runtime collector reads `nft -j`, correlates semantic IDs with current handles and counters, and detects drift.

`routerctl firewall explain` should accept source/destination zones or concrete addresses, family, protocol, ports, input/output interfaces, and optionally connection state. Output should include:

- final verdict;
- ordered evaluation trace;
- matched topology policy and its source path;
- implicit rules such as established/related or default drop;
- generated semantic rule ID;
- live nftables chain, handle, and counter when available;
- whether policy intent and kernel state agree.

Do not store nftables handles in the build artifact: handles are runtime values and can change after reload. Stable comments or explicit rule IDs are the correlation key.

For diagnostics, define a versioned envelope such as:

```json
{
  "schemaVersion": 1,
  "generatedAt": "...",
  "overall": "degraded",
  "components": [],
  "errors": []
}
```

Recommended commands:

- `routerctl status --format json`: current interfaces, routes, addresses, DHCP/DNS, BGP, VRRP, translation, firewall, and qdisc state.
- `routerctl health --format json`: stable check IDs, severity, evidence, remediation, and exit codes.
- `routerctl diagnostics --output ...`: bounded support bundle with an explicit redaction manifest.
- `routerctl hardware --format json`: requested/available/effective optimization states.
- `routerctl firewall explain ...`: offline intent by default, with `--live` for kernel correlation.

JSON must be the stable contract; human tables and Prometheus output should be renderers over the same internal model. Diagnostics must omit lease identities, DNS query contents, credentials, private keys, and unrestricted journals by default.

`[satisfied]`

## Q4 — Core decoupling and failure isolation

The critique is right about the dependency boundary, but “containerize observability” is too broad. Profiles control composition; slices and sandboxing control failure propagation; containers or microVMs control trust and namespaces. These solve different problems.

Adopt three explicit tiers:

- `core`: networkd, nftables, routing, HA, DHCP, selected DNS backend, translation, and QoS.
- `observability`: ulogd, flow exporters, ntopng, Netdata, metrics, and log processing.
- `applications/control access`: dashboard, reverse proxies, homelab services, and optional remote-management systems.

Not every tunnel belongs outside core. A tunnel carrying production routing or emergency administration may be core; an application-publishing tunnel is not. Classification needs an explicit operational role rather than module-name heuristics.

Default isolation:

- Put observability units in `router-observability.slice` with `MemoryHigh`, `MemoryMax`, `CPUQuota`, `TasksMax`, and conservative I/O weights.
- Apply systemd sandboxing per daemon: read-only filesystem, restricted address families, bounded capabilities, private temporary storage, and no device access unless required.
- Ensure core units do not `Requires=` or `After=` optional telemetry except where purely ordering-related.
- Configure logging limits so a broken exporter cannot exhaust persistent storage.
- Use restart backoff for peripheral services; crash loops must become health warnings rather than unlimited resource consumption.

Containers are appropriate for dependency-heavy or poorly trusted applications, but host-network observability often loses much of a container’s isolation benefit. MicroVMs should be opt-in for genuinely untrusted workloads or strong kernel boundaries, not the router default.

Do not promise that `MemoryMin` or `OOMScoreAdjust` makes the core invulnerable. Validate failure behavior by deliberately exhausting telemetry memory, filling its log quota, and crash-looping it while forwarding traffic through a VM test.

`[satisfied]`

## Q5 — VM integration tests and compatibility matrix

The absence is real: [tests/README.md](/home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/roundtable-20/tests/README.md:1) explicitly describes evaluation-oriented checks and says VM tests are not yet part of the matrix.

Start with one reusable four-node topology:

```text
lanClient ── LAN ── router ── WAN ── wanSimulator
                         │
                    guestClient
```

`wanSimulator` should provide upstream DHCP, authoritative/recursive DNS test zones, HTTP/HTTPS endpoints, an IPv4-only endpoint for translation tests, and later a BGP peer. Use deterministic private addressing and no external network dependency.

The first runtime suite should test:

1. networkd convergence and stable interface roles;
2. DHCP lease, gateway, DNS, renewal, and reservation;
3. LAN-to-WAN forwarding and source NAT;
4. unsolicited WAN ingress rejection;
5. LAN/guest zone isolation in both directions;
6. permitted stateful return traffic;
7. DNS forwarding and local overrides;
8. firewall reload without losing established connectivity;
9. `routerctl` JSON schema and health exit codes;
10. reboot persistence.

Then add specialized topologies:

- two routers for VRRP ownership and bounded failover;
- IPv6-only client plus IPv4 server for NAT64/DNS64;
- BGP peer advertisement and withdrawal;
- bandwidth-limited link for CAKE tests.

Latency targets must be calibrated to virtual scheduling noise. A hard “single-digit milliseconds” CI assertion will be flaky; compare CAKE-on versus CAKE-off distributions or use a generous regression threshold. Hardware performance remains a separate HIL concern.

The compatibility matrix should distinguish `supported`, `CI-tested`, `hardware-tested`, `experimental`, and `unsupported`. Initial honest scope:

| Axis | Initial commitment |
|---|---|
| Architecture | x86_64 full VM tests; aarch64 evaluation/build initially |
| Platform | QEMU CI-tested; physical hardware documented/HIL-tested |
| NIC | virtio CI-tested; igb/igc/r8169/ixgbe tested only when runners exist |
| Addressing | IPv4 and dual-stack CI-tested; IPv6-only experimental until translation tests land |
| WAN | static and DHCP CI-tested; PPPoE/DS-Lite separately qualified |
| HA | single-router first; VRRP pair after deterministic failure tests |
| Profiles | core first, then core+observability and full |

Do not mark an entire architecture supported merely because it evaluates.

`[satisfied-conditional: matrix cells report evidence levels rather than aspirational support]`

## Q6 — Roadmap and priorities

Yes: adopt a temporary freeze on new feature families. Permit fixes, assertion work, diagnostics, tests, dependency updates, and narrowly scoped changes required to make existing functionality testable. Exit the freeze using measurable gates rather than only a date.

Priority order:

**P0 — Remove unsafe behavior**

1. Replace blanket offload enablement and remove forwarding-interface LRO defaults.
2. Make optimization failures visible.
3. Fix any known invalid nftables generation paths.
4. Add regression checks for these failures.

**P1 — Establish the contract**

5. Define the normalized, versioned topology model.
6. Centralize cross-module validation and add negative evaluation tests.
7. Document core/observability/application ownership and dependency rules.
8. Rewrite positioning without claiming unfinished derivations.

**P2 — Prove basic routing**

9. Add the client/router/guest/WAN-simulator NixOS test harness.
10. Cover DHCP, forwarding, NAT, isolation, DNS, reload, and reboot.
11. Require relevant runtime tests for changes to core networking behavior.

**P3 — Build operational inspection**

12. Specify versioned JSON schemas.
13. Implement `routerctl status` and `health`.
14. Add semantic firewall rule IDs and `firewall explain`.
15. Add redacted support bundles while retaining `router-diag` as the minimal fallback.

**P4 — Isolate and qualify**

16. Introduce resource-controlled slices and per-unit sandboxing.
17. Test observability crash, OOM, and disk-pressure scenarios.
18. Publish the evidence-based compatibility matrix.
19. Add HA, translation, BGP, and CAKE runtime suites.
20. Establish HIL coverage before making NIC-specific performance claims.

Freeze exit criteria should include: all P0/P1 work complete; basic three/four-node runtime tests gating CI; structured health available; core/optional failure boundaries tested; and compatibility documentation containing no unsupported blanket claims.

The critique’s main direction is correct. Its largest misunderstandings are that the repository already uses networkd/nftables and already has many local assertions. The maturation task is integration: unify topology, validate across modules, observe runtime truth, and test complete packet paths.

`[satisfied]`

---

### 4. GitHub Copilot CLI Voice

## Q1 — Positioning & Framework Identity

**Verdict: Yes, rebrand immediately.** README.md line 3 literally reads *"RouterOS-like performance optimizations for home/small business routers"* — this is the wrong headline. RouterOS comparisons invite feature-parity arguments (VPN wizards, GUI parity, wireless controller) this project isn't built to win, and they bury the actual asset: `modules/router-zones.nix` already derives firewall policy from a typed zone graph with build-time `assertions` (lines 133–161) — that's the real differentiator, not packet-per-second numbers.

**Exact differentiation vs. `chayleaf/nixos-router`:**
- `nixos-router` is primarily a lower-level networking/NAT abstraction (interfaces, routing, port-forwarding as NixOS options). It does **not** ship a zone-based policy model with cross-referential eval-time validation, HA/VRRP orchestration, CLAT/NAT64/DNS64, or a diagnostics CLI.
- This project's differentiation is the **pipeline**, not any single feature: *typed topology (zones, interfaces, policies) → derived nftables/Kea/Unbound config → build-time-verified invariants → reproducible flake deployment → measurable, falsifiable performance claims.* Each arrow is inspectable and testable; that's what RouterOS/OpenWrt/nixos-router don't offer together.
- Concrete action: rewrite README opening paragraph and `docs/work-items/START-HERE.md` framing around this four-stage pipeline; move performance claims to a benchmarks appendix with methodology, not the pitch.

`[satisfied]`

---

## Q2 — Safety, Assertions & Hardware Safety Boundaries

Assertions already exist (`router-zones.nix`, `router-firewall.nix:494-508`, `router-networking.nix:647-662`, `router-optimizations.nix:77-79`) but coverage is uneven. Immediate additions:
- **Topology-level**: overlapping IPv4/IPv6 prefixes across zones/interfaces; duplicate static/DHCP pool ranges; duplicate VRRP VIPs across `router-ha.nix` instances (currently unchecked); MTU mismatches between an interface and any VLAN/PPPoE/CLAT stack riding on it; dangling zone references already covered but should extend to DNS zone (`dns-zone.nix`) and BGP peer definitions.
- **Cross-module**: `router-mwan.nix` route weights referencing undefined WAN interfaces; Kea/Technitium reservation IP falling outside its subnet's pool.

**Hardware optimization flags — this is a real gap.** `modules/router-optimizations.nix:178-235` blindly runs `ethtool -K ... on || true` for every offload on every WAN interface with no capability query and no reported outcome — a `supported/enabled/effective/reason-disabled` state machine doesn't exist today. Concrete fix:
1. Replace the fire-and-forget `ethtool` invocation with a script that first runs `ethtool -k $iface` to read `[fixed]` vs. mutable features, attempts the toggle, re-reads state, and writes results to `/run/router-optimizations/<iface>.json` as `{feature, supported, requested, effective, reason}`.
2. Surface this via `router-diag show optimizations` (ties into Q3) instead of silently swallowing failures.
3. XDP/CAKE should follow the same pattern — CAKE already binds to qdisc (`router-sqm.nix`) which fails loudly if unsupported; XDP does not currently exist in this repo and should not be added without this capability-reporting groundwork first (ties into Q6 freeze).

`[satisfied-conditional: hardware-capability state machine ships before any XDP module is introduced]`

---

## Q3 — Firewall Explainability & CLI Diagnostics

`pkgs/router-diag/router-diag.sh` (119 lines) is a thin bash wrapper today: `show interfaces`, `show firewall` (just `nft list ruleset | grep counter`), `show vpn`, `show health`. It has no `explain` verb and no structured/JSON output — critique #7 and #10 are both accurate gaps.

**Architecture proposal:**
- Add `router-diag explain --source <zone> --dest <zone> --proto tcp --port 443`. Since `router-zones.nix` already compiles zone policies into deterministic nftables chain/rule names (verify naming convention in generated ruleset), the explain command should: (a) resolve source/dest zone → chain name, (b) run `nft -j list ruleset` (JSON output mode, already supported by nftables), (c) walk the JSON rule list for matches on proto/port within that chain, (d) print the matched rule plus counters plus the originating Nix policy attribute path (requires embedding a `# from: zones.lan.policies.<name>` comment or JSON meta annotation during rule generation in `router-firewall.nix`).
- Add `router-diag status --json` / `router-diag health --json` as machine-readable variants of existing `show health` — trivial: emit structured objects instead of colored text, keep colored text as the human-facing default.
- This builds **directly** on existing infrastructure (nftables JSON API + already-deterministic zone→chain naming) — no new dependency needed beyond `nft -j`.

`[satisfied-conditional: verify router-firewall.nix rule generation already tags rules with stable identifiers traceable back to zone policy attrs — if not, that tagging is a prerequisite work item before "explain" can be built]`

---

## Q4 — Core Decoupling & Failure Isolation

Currently there is **no** systemd slice, container, or microVM isolation for observability (`grep` for `containers.`, `microvm`, `Slice=` across `modules/*.nix` returned nothing relevant — only an unrelated hit in `router-rgbdns.nix`). `router-observability.nix`, `router-ntopng.nix`, `router-dashboard.nix`, `router-homelab.nix`, `caddy-reverse-proxy.nix` all run as ordinary systemd services alongside `router-firewall.nix`/`router-kea.nix`/`router-dhcp.nix`.

**Recommendation — three-tier, incrementally adoptable:**
1. **Immediate (low cost)**: systemd resource isolation via `Slice=router-observability.slice` + `MemoryMax`/`CPUQuota` on ntopng, ulogd/flow exporters, and dashboard units so a runaway/crashing plugin can't starve conntrack, DHCP leases, or DNS resolution. This is a few-line change per unit and should happen regardless of the larger architecture decision.
2. **Medium term**: split the flake's `nixosModules` export into three explicit groups — `nixosModules.core` (zones, firewall, dhcp, dns, ha, clat/nat64/dns64, sqm), `nixosModules.observability` (monitoring, ntopng, dashboard, log-storage), `nixosModules.applications` (caddy, tunnels, remote-admin, homelab). A minimal "core-only" profile becomes a first-class, testable target (ties into Q5's compatibility matrix).
3. **Longer term**: containerize peripheral C-plugin-dependent tools (ulogd, flow exporters) via `systemd-nspawn`/NixOS `containers.*` — not full microVMs, which add virtio-net complexity disproportionate to the isolation benefit for what are effectively read-only telemetry consumers of netlink/nftables counters. MicroVMs are justified only if a plugin needs kernel-module-adjacent privileges that must not leak host capabilities.

`[satisfied-conditional: start with systemd slices immediately; defer container/microVM decision until after the core/observability/application module-group split lands and profile-based testing (Q5) proves the split is clean]`

---

## Q5 — Automated NixOS VM Integration Tests & Compatibility Matrix

This is the single biggest actionable gap. `tests/` has 20+ files but they are **all** eval-time checks via `mkNixosEvalCheck`/`mkNixosEvalFailureCheck` (`tests/nixos-eval.nix`) — building `system.build.toplevel` and asserting eval success/failure. There is no `nixosTest`/`testScript`/QEMU multi-node test anywhere in the repo. Critique #4 is fully correct.

**Proposed topology** (new `tests/vm/` directory, wired into `flake.nix` `checks`):
```
nodes = { client, router, wanSim };
```
- `wanSim`: minimal node acting as upstream ISP — runs a DHCP/PPPoE-like server or static addressing on the router's WAN interface, plus a target host to prove outbound NAT reachability.
- `router`: boots the actual flake config (a minimal core-only profile per Q4) with `lan0`↔client, `uplink0`↔wanSim.
- `client`: plain NixOS node on LAN, requests a Kea/systemd-networkd DHCP lease, resolves via Unbound/Technitium, and attempts to reach a service behind wanSim to prove NAT + firewall zone policy (lan→wan allowed, wan→lan denied by default).
- Test scenarios: (1) DHCP lease acquisition + correct DNS options, (2) firewall zone isolation (assert wan-initiated connection to LAN client is refused), (3) failover — two router nodes with VRRP, kill the master, assert client's route/gateway still reachable via VIP within N seconds, (4) SQM/CAKE qdisc actually attaches without erroring in the VM (validates config wiring, not real bufferbloat numbers, which VMs can't measure meaningfully).

**Compatibility matrix (initial, minimal but explicit)**:

| Axis | Values | Status |
|---|---|---|
| Arch | x86_64-linux, aarch64-linux | x86_64 tested; aarch64 eval-only until VM/HW runners exist |
| Platform | QEMU VM, bare metal | VM = CI-gated; bare metal = manual runbook (`docs/work-items/*runbook*`) |
| IP stack | IPv4-only, dual-stack, CLAT/NAT64/DNS64 | dual-stack primary; CLAT path has its own eval fixtures already (`router-clat`) |
| NIC driver class | virtio (VM), generic ethtool-capable | Only virtio validated in CI; real NIC offload matrix is a manual/community-sourced table |

This matrix should live as a markdown table in README/docs and be referenced, not aspirational — mark untested cells "untested" rather than omitting them.

`[satisfied-conditional: nixosTest infra added to flake.nix checks as new CI gate, even if initially covering only scenario (1) and (2) — failover and SQM scenarios can follow incrementally]`

---

## Q6 — Roadmap & Work Item Priorities

**Support a temporary feature freeze — with a narrow, defensible definition.** The `docs/work-items/` backlog (94+ numbered items, many about NDP proxy, IPv6 multi-WAN, CLAT backend abstraction, DHCP option 108) shows steady feature accretion. A freeze should mean: *no new modules/services*, not *no work*. Boundary/hardening/backend-parity work already in flight (e.g., `80-router-translation-backend-shared-adapter-surface.md`, `86-router-security-validation-runbook.md`) is compatible with a freeze since it's about validating existing surface area, not adding new services.

**Immediate work items, in priority order:**
1. VM-based `nixosTests` skeleton (Q5) — highest leverage, currently zero coverage of runtime behavior vs. ~20 eval-only test files.
2. Hardware-capability reporting for `router-optimizations.nix` (Q2) — cheap, high safety value, unblocks honest performance claims.
3. `router-diag explain` + JSON output modes (Q3) — directly answers the "zones hide policy" critique with a shippable tool, likely 1-2 weeks of focused work given nftables JSON API already exists.
4. Module group split into `core`/`observability`/`applications` flake outputs (Q4) — enables the "core-only" compatibility matrix row and is a prerequisite for meaningful minimal-footprint testing.
5. README/positioning rewrite (Q1) — cheap, should ship alongside item 3 as the external-facing proof point.
6. Compatibility matrix doc (Q5) — publish even in "aspirational/untested" form now, refine as CI coverage grows.

Items like VRRP-VIP-duplicate assertions and MTU-consistency checks (Q2) are small enough to bundle into whichever PR touches `router-ha.nix`/`router-networking.nix` next, rather than scheduling separately.

`[satisfied-conditional: freeze scope is explicitly documented as "no new service modules" rather than "no commits," to avoid stalling the safety/testing work this roadmap depends on]`

---

## Convergence & Core Decisions

The multi-agent roundtable achieved complete unanimity across all six core questions:

### 1. Positioning Rebrand (Q1)
- **Decision:** Formally deprecate "RouterOS-inspired performance" across `flake.nix`, `README.md`, and module comments.
- **New Identity:**  
  **"A typed, topology-driven declarative router framework for NixOS: Deterministic edge networking, zone security, and resilient protocol orchestration."**
- **Core Pipeline:** `typed topology -> derived firewall/DHCP/DNS/QoS -> reproducible deployment -> measurable performance`.
- **Differentiation vs. `chayleaf/nixos-router`:** While `chayleaf/nixos-router` is a single-host router module based on network namespaces (`netns`) and custom shell wrappers that explicitly rejects `systemd-networkd`, `nix-router-optimized` standardizes purely on upstream native `systemd-networkd` and pure `nftables`, providing multi-node HA (VRRP, BGP promotion, WAN MAC cloning), multi-zone security, and transition architectures (464XLAT/CLAT, NAT64, DNS64).

### 2. Immediate Forwarding Safety & Invariant Assertions (Q2)
- **Decision:** **Purge `lro on` immediately.** In `modules/router-optimizations.nix`, the script blindly forces `ethtool -K $iface lro on`. In Linux, LRO reassembles TCP payloads without preserving transport checksums or original packet boundaries; running LRO on a forwarding router corrupts forwarded TCP traffic and breaks conntrack/NAT. Enforce `ethtool -K $iface lro off` on all routed interfaces.
- **Decision:** Implement pure Nix eval-time assertions in `lib/assertions.nix`:
  - Interface CIDR prefix overlap checks across all routed interfaces.
  - DHCP pool containment within interface subnets.
  - VLAN MTU $\le$ parent interface MTU.
  - VRRP VIP uniqueness against static node IPs on the segment.
- **Decision:** Model hardware offloads using the 4-state matrix (`supported`, `enabled`, `effective`, `reason disabled`), recorded at runtime in `/run/router/nic-offload-status.json`.

### 3. `routerctl` CLI Diagnostics & Firewall Explainability (Q3)
- **Decision:** Refactor `router-diag.sh` into `routerctl` with structured `--json` schema output (`routerctl status`, `health`, `diagnostics`), retaining human-readable colored tables as the default for interactive SSH.
- **Decision:** Implement `routerctl firewall explain` using a two-tier architecture:
  - *Tier 1 (Static Policy Graph):* Export the compiled zone policy matrix at build time to `/etc/router/policy-manifest.json`. Enables instant, zero-packet explanations of zone rules, policies, and target nftables chains.
  - *Tier 2 (Live Packet Tracing):* Ephemeral `nft monitor trace` hooks for live debugging of kernel packet paths.

### 4. Core Decoupling & Failure Slicing (Q4)
- **Decision:** Decouple core routing from telemetry using **systemd resource slices** rather than containers or microVMs:
  - `router-core.slice`: High priority (`OOMScoreAdjust=-900`, protected memory, `Restart=always`) for `systemd-networkd`, `nftables`, `kea`, `unbound`, `keepalived`.
  - `router-observability.slice`: Strict limits (`MemoryMax=256M`, `CPUQuota=30%`) for `ulogd`, `netdata`, `ntopng`.
  - `router-applications.slice`: Isolated execution (`MemoryMax=512M`, `CPUQuota=50%`) for Caddy, Tailscale, remote administration.
- **Decision:** Ensure that telemetry daemon crashes or log storms never disrupt core packet forwarding.

### 5. Automated QEMU VM Integration Tests & Compatibility Matrix (Q5)
- **Decision:** Transition beyond pure evaluation checks (`mkNixosEvalCheck`).
- **Decision:** Implement a multi-node QEMU VM test harness in `tests/vm/` using `pkgs.testers.runNixOSTest`:
  ```text
  lanClient ── LAN ── router ── WAN ── wanSimulator
                           │
                      guestClient
  ```
  Automates verification of DHCP lease distribution, NAT masquerade forwarding, local DNS resolution, and firewall zone isolation drops in headless QEMU.
- **Decision:** Publish an evidence-based compatibility matrix in `docs/COMPATIBILITY.md` distinguishing `CI-tested`, `hardware-tested`, `experimental`, and `untested`.

### 6. Maturation Freeze & Scheduled Work Items (Q6)
- **Decision:** Enact a temporary feature freeze on new networking services and UI additions in favor of hardening, test automation, and diagnostics.
- **Decision:** Schedule five sequential work items (WI-95 through WI-99) to execute the roadmap.

---

## Actionable Work Items Derived from Consensus

The following work items are added to `docs/work-items/`:

| Work Item | Title & Description | Priority |
|---|---|---|
| **[WI-95](./95-hardware-optimization-safety-matrix-and-lro-removal.md)** | **Hardware Optimization Safety Matrix & LRO Removal:** Purge hazardous `lro on` from `router-optimizations.nix`, enforce safe GRO defaults, and implement driver-aware capability negotiation and `/run/router/nic-offload-status.json`. | **P0 (Blocker)** |
| **[WI-96](./96-multi-node-nixos-vm-test-harness.md)** | **Multi-Node NixOS VM Test Harness:** Establish `tests/vm/` with `wanSimulator <-> router <-> client` QEMU integration test verifying DHCP, NAT, DNS forwarding, and zone isolation. | **P0 (Blocker)** |
| **[WI-97](./97-routerctl-cli-diagnostics-and-firewall-explainer.md)** | **`routerctl` Structured CLI Diagnostics & Firewall Explainer:** Refactor `pkgs/router-diag` into `routerctl` with JSON schema output, and build `routerctl firewall explain` backed by compile-time `/etc/router/policy-manifest.json`. | **P1 (High)** |
| **[WI-98](./98-subnet-overlap-and-topology-eval-assertions.md)** | **Subnet Overlap, MTU & Topology Invariant Assertions:** Implement pure Nix CIDR calculation in `modules/lib/ip.nix` and assert non-overlapping prefixes, DHCP pool containment, VLAN MTU invariants, and VRRP VIP uniqueness. | **P1 (High)** |
| **[WI-99](./99-systemd-slice-isolation-and-framework-rebranding.md)** | **Systemd Slice Resource Isolation & Framework Rebranding:** Introduce `router-core.slice` vs. `router-observability.slice` with memory bounds, update `flake.nix` and `README.md` to formalize the topology-driven framework identity, and publish `docs/COMPATIBILITY.md`. | **P2 (Medium)** |

---

## Maintained Line

The maintained line after Round 20 is:

1. **Framework Identity:** `nix-router-optimized` is positioned as a typed, topology-driven NixOS router framework prioritizing deterministic edge configuration and verifiable performance.
2. **Forwarding Safety:** LRO is strictly prohibited on forwarding interfaces; offloads must be negotiated safely per NIC driver.
3. **Fail-Fast Evaluation:** Network topology errors (subnet collisions, pool overflows, MTU violations) must fail evaluation immediately via pure Nix assertions.
4. **Resilient Architecture:** Core forwarding and control daemons run in protected systemd slices isolated from telemetry resource spikes.
5. **Empirical Verification:** The repository requires multi-node NixOS QEMU VM tests in CI to validate routing, firewall, and DHCP invariants before bare-metal deployment.
