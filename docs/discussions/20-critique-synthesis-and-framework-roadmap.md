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
- **Gemini CLI** (Gemini Pro via `agy --dangerously-skip-permissions -p`). Focused on operational router deployment, declarative NixOS abstractions, firewall inspection, and VM smoke topologies.
- **GitHub Copilot / Discussion Leader IC Voice** (Technical synthesis, disconfirmation analysis, and project roadmap translation).
- **Explicit Record of Degraded / Unavailable Seats:**
  - *Codex CLI:* Degraded/Unavailable. Executed `codex exec`, returned HTTP 401 Unauthorized (`failed to connect to websocket: HTTP error: 401 Unauthorized, url: wss://api.openai.com/v1/responses`).
  - *Claude Code CLI:* Degraded/Unavailable. Executed `claude -p`, returned `Not logged in · Please run /login`.
  - *OpenCode Enrichment Seat:* Degraded/Unavailable. Executed `opencode run -m opencode/nemotron-3-ultra-free`, provider process hung indefinitely during environment bootstrap.

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

---

## Voice Summaries

### 1. DeepSeek API Voice

```markdown
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

```

---

### 3. GitHub Copilot / Discussion Leader IC Voice

- **On Q1 (Positioning & Framework Identity):**
  - Concur with DeepSeek and Gemini. "RouterOS-inspired performance" was an early historical descriptor for kernel conntrack sizing, TCP BBR, and flowtable fastpath offloading. Retaining it as a primary badge is a liability because it invites comparisons to MikroTik's monolithic, closed-source appliance software and Winbox GUI, while obscuring what makes `nix-router-optimized` technically unique.
  - The project's actual identity is: **A declarative, composable NixOS router distribution driven by a typed network topology, deriving strict firewall/DHCP/DNS configurations, providing reproducible edge deployment and verifiable performance.**
  - Against `chayleaf/nixos-router`: `chayleaf/nixos-router` relies heavily on network namespaces (`netns`) and custom shell wrappers, explicitly avoiding `systemd-networkd`. `nix-router-optimized` adopts native upstream `systemd-networkd` and pure `nftables`, adding high-availability (VRRP, keepalived, BGP neighbor promotion, WAN MAC cloning), multi-zone containment, and declarative transition tools (464XLAT/CLAT, NAT64, DNS64).
  - *Satisfaction:* `[satisfied]`

- **On Q2 (Safety, Assertions & Hardware Boundaries):**
  - Concur with the critical discovery: [modules/router-optimizations.nix](file:///home/deepwatrcreatur/flakes-worktrees/nix-router-optimized/main/modules/router-optimizations.nix#L206) currently runs `ethtool -K $iface lro on 2>/dev/null || true`. **LRO (Large Receive Offload) must be purged immediately.** LRO destroys original packet headers and reassembles TCP payloads without preserving checksums, corrupting transit routed traffic. Forwarding routers must use GRO (Generic Receive Offload), never LRO.
  - Assertions: Build-time eval assertions are a core Nix strength. Implement `lib/assertions.nix` covering CIDR prefix overlap, DHCP pool containment within interface subnets, VLAN MTU <= parent MTU, and VRRP VIP uniqueness.
  - Hardware Offload Model: Adopt the 4-state matrix (`supported`, `enabled`, `effective`, `reason disabled`). Since Nix eval cannot query physical sysfs on the build machine, enforce compile-time profile bounds (`intel-baremetal`, `realtek-baremetal`, `virtio-vm`) combined with activation-time `ethtool -k` status logging to `/run/router/nic-offload-status.json`.
  - *Satisfaction:* `[satisfied]`

- **On Q3 (Firewall Explainability & CLI Diagnostics):**
  - Concur with the two-tier approach. In Linux, nftables has no built-in offline simulation engine. Therefore, `routerctl firewall explain` must be driven by an exported declarative policy manifest (`/etc/router/policy-manifest.json`) generated at Nix build time from `services.router-zones`. This allows zero-packet instantaneous explanations of zone policies. For live packet tracing, provide `routerctl firewall trace` using ephemeral `nft monitor trace` hooks.
  - Evolve `router-diag.sh` into `routerctl`, standardizing on JSON output (`--json`) for machine consumption alongside formatted terminal tables.
  - *Satisfaction:* `[satisfied]`

- **On Q4 (Core Decoupling & Failure Isolation):**
  - Concur that heavy microVMs or OCI containers are counterproductive for telemetry daemons like `ulogd` or `prometheus-node-exporter`, because they need direct access to host network interfaces and sockets, and microVMs impose significant memory overhead on low-power edge routers.
  - Instead, use **systemd resource slices**:
    - `router-core.slice`: Unbounded CPU, protected memory (`MemoryMin=`), high OOM protection (`OOMScoreAdjust=-900`) for `systemd-networkd`, `nftables`, `kea`, `unbound`, `keepalived`.
    - `router-observability.slice`: Strict limits (`MemoryMax=256M`, `CPUQuota=30%`) for `ulogd`, `netdata`, `ntopng`.
    - `router-applications.slice`: Isolated execution (`MemoryMax=512M`, `CPUQuota=50%`) for Caddy, Tailscale, remote administration.
  - *Satisfaction:* `[satisfied]`

- **On Q5 (Automated NixOS VM Integration Tests & Compatibility Matrix):**
  - Concur that relying solely on `mkNixosEvalCheck` (pure evaluation) is a major coverage gap. Implement a lightweight 3-node QEMU test harness in `tests/vm/` using `pkgs.testers.runNixOSTest` (`wanSimulator <-> router <-> client`).
  - The VM test suite will verify: WAN DHCP lease, LAN DHCP lease distribution, NAT masquerade forwarding, DNS resolution, and zone drop enforcement.
  - Maintain an explicit compatibility matrix in `docs/COMPATIBILITY.md` documenting validated tiers (Proxmox/KVM virtio, Intel NICs, Realtek, ARM64 SBCs).
  - *Satisfaction:* `[satisfied]`

- **On Q6 (Roadmap & Work Item Priorities):**
  - Concur with an immediate **Hardening & Maturation Freeze**. Halt new service modules (e.g. OSPF, EVPN) to execute the P0/P1 stability roadmap.
  - *Satisfaction:* `[satisfied]`

---

## Convergence & Core Decisions

The multi-agent roundtable achieved full unanimity across all six questions:

### 1. Positioning Rebrand
- **Decision:** Formally deprecate "RouterOS-inspired performance" in favor of:  
  **"A typed, topology-driven declarative router framework for NixOS: Deterministic edge networking, zone security, and resilient protocol orchestration."**
- **Core Pipeline:** `typed topology -> derived firewall/DHCP/DNS -> reproducible deployment -> measurable performance`.

### 2. Immediate Safety Assertions & Hardware Boundaries
- **Decision:** Immediately purge `lro on` from `router-optimizations.nix`. Enforce `lro off` on all routed interfaces.
- **Decision:** Implement eval-time topology assertions in `lib/assertions.nix`:
  - Interface CIDR prefix overlap checks.
  - DHCP pool containment within interface subnets.
  - VLAN MTU $\le$ parent interface MTU.
  - VRRP VIP uniqueness against static node IPs.
- **Decision:** Model hardware offloads using the 4-state paradigm (`supported`, `enabled`, `effective`, `reason disabled`), recorded at runtime in `/run/router/nic-offload-status.json`.

### 3. `routerctl` CLI Diagnostics & Firewall Explainability
- **Decision:** Upgrade `router-diag` to `routerctl` featuring structured JSON outputs (`--json`) across `status`, `health`, and `diagnostics`.
- **Decision:** Implement `routerctl firewall explain` backed by a static compile-time export of the zone policy graph (`/etc/router/policy-manifest.json`), supplemented by `--live` tracing via ephemeral `nftrace` rules.

### 4. Systemd Slice Failure Isolation
- **Decision:** Decouple core routing from telemetry using systemd resource slices (`router-core.slice` vs. `router-observability.slice`).
- **Decision:** Protect core routing units with `OOMScoreAdjust=-900` and cap telemetry services with `MemoryMax=256M`, ensuring that memory leaks or crashes in logging daemons (`ulogd`, `ntopng`) never disrupt packet forwarding.

### 5. Automated QEMU VM Integration Tests
- **Decision:** Implement multi-node QEMU VM integration tests in `tests/vm/` using `pkgs.testers.runNixOSTest`.
- **Decision:** Stand up the baseline 3-node test topology (`wanSimulator <-> router <-> client`) verifying DHCP, NAT traversal, DNS, and zone firewall drops.
- **Decision:** Document a platform compatibility matrix in `docs/COMPATIBILITY.md`.

### 6. Maturation Freeze & Scheduled Work Items
- **Decision:** Enact a temporary feature freeze on new networking protocols and UI additions, scheduling five sequential work items (WI-95 through WI-99) to execute the consensus roadmap.

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
