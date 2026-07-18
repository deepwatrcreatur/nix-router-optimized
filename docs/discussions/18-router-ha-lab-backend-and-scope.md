# Discussion 18: What Should Be the First Safe HA Lab Backend for `nix-router-optimized`?

**Status:** closed
**Opened:** 2026-07-18
**Participants requested:** Codex CLI, Gemini CLI, DeepSeek API, and GitHub Copilot CLI

## Why this discussion exists

Recent live homelab HA and failover work repeatedly disrupted the real router.
The current validated operating model has been simplified back to:

- one active production router
- one cold/manual spare
- HA deferred until it can be developed more safely

The next design question is therefore not "how do we keep pushing live HA?" but
rather:

- what isolated development and testing environment should be introduced first
  so future HA work stops depending on risky homelab deployments?

The candidate under consideration is a `systemd-nspawn` / NixOS-container lab
that can simulate:

- `router`
- `router-backup`
- a fake upstream
- a LAN client

The narrower design question for this round is:

- should `systemd-nspawn` be the first serious lab backend?
- what should phase 1 include?
- what should it explicitly not try to prove?

## Relevant current local context

From the repo and adjacent deployment work:

- `router-ha` remains a supported upstream module surface, but the reference
  homelab pair is no longer being treated as proven live HA
- the current stable deployment posture is one active router plus one
  cold/manual spare
- the repo already has strong eval-boundary checks and discussion/work-item
  discipline, but no serious booted multi-node HA lab harness
- the real gap is safe iteration on:
  - keepalived / VRRP behavior
  - service ownership transitions
  - promotion / demotion behavior
  - failover drills that do not touch the real home network

## Source material reviewed

- [`docs/router-ha-ownership.md`](../router-ha-ownership.md)
- [`docs/router-dhcp-single-active.md`](../router-dhcp-single-active.md)
- [`tests/router-ha-boundaries.nix`](../../tests/router-ha-boundaries.nix)
- the live shared round prompt saved during execution as
  `/tmp/router_lab_round_prompt.txt`

## Participation record

This round was **degraded** and must not be mistaken for a complete normal
quorum.

What actually happened:

- **Codex CLI:** substantive
- **DeepSeek API:** substantive
- **Gemini CLI:** failed at authentication time because the local Gemini Code
  Assist client on this host is no longer supported for the current individual
  tier
- **GitHub Copilot CLI:** unavailable in this interface
- **OpenCode enrichment seat:** attempted, but failed with an upstream server
  error

This discussion is therefore recorded as a **degraded two-seat substantive
round** with explicit missing seats, not as a normal full-roster result.

## Voice summaries

### Codex CLI

- Core recommendation:
  start with `systemd-nspawn`, but only as a bounded control-plane lab rather
  than a full realism claim.
- Strongest points:
  - `nspawn` wins on iteration speed and easy reuse of the repo's NixOS module
    stack
  - it is good enough for keepalived / VRRP ownership behavior, systemd unit
    promotion logic, and safe failover drills
  - it is not good enough to prove hardware-grade or packet-timing realism
- Recommended next move:
  build a small `router` / `router-backup` / `wan` / `client` topology first,
  keep DHCP automatic failover out of phase 1, and later promote the strongest
  scenarios into NixOS VM tests

### DeepSeek API

- Core recommendation:
  adopt `systemd-nspawn` as the first lab backend because the immediate need is
  fast safe iteration, not full realism.
- Strongest points:
  - containers are good enough for VRRP/keepalived startup ordering, state
    transitions, and simulated link failure drills
  - the first topology should stay deliberately simple and disconnected from the
    real LAN/WAN
  - the lab should remain a manual design-exploration environment until the
    scenarios are proven and ready to graduate into VM tests
- Recommended next move:
  start with two router containers plus a fake upstream and a simple client,
  enforce hard host-side network isolation, and keep automation light until the
  basic failover story is trustworthy

## First-pass convergence

Despite the degraded roster, the two substantive seats converged strongly on the
same structure.

1. **`systemd-nspawn` is the right first backend.**
   Not because it is maximally realistic, but because it is the fastest safe
   environment for iterating on HA control-plane behavior.

2. **The lab should have a deliberately narrow charter.**
   Phase 1 should prove only:
   - VIP / VRRP behavior
   - service ownership transitions
   - bounded promotion / demotion drills
   - safe host-local isolation

3. **Phase 1 should stay small.**
   The first useful topology is:
   - `router`
   - `router-backup`
   - `wan` or `upstream-sim`
   - `client`

4. **Automatic DHCP failover should not be part of phase 1.**
   The repo's current reference truth is still manual/single-active DHCP
   ownership, so the lab should not over-claim beyond that reality.

5. **Successful `nspawn` scenarios should later become NixOS VM tests.**
   The lab is for fast scenario discovery and safe rehearsal; CI-grade
   regression proof should come later from VM tests.

## Main disagreements or differences in emphasis

There was no meaningful substantive disagreement on the backend choice.

The difference was mainly emphasis:

- Codex leaned harder on keeping the lab explicitly separate from CI and from
  any claim of router-grade realism
- DeepSeek leaned harder on a concrete bridge-based container layout and
  specific host firewall isolation rules

These are complementary rather than conflicting positions.

## Final synthesis

`systemd-nspawn` should be adopted as the **first serious isolated HA lab
backend** for `nix-router-optimized`, but only with a narrow charter:

- fast control-plane iteration
- safe host-local failover drills
- bounded evidence for ownership and promotion behavior

It should **not** be treated as the final authority for production-grade
realism.

The correct staged model is:

1. use `nspawn` to learn safely and quickly
2. stabilize a small set of scenarios
3. promote those scenarios into NixOS VM tests
4. only then expand toward more ambitious HA surfaces

## One-sentence verdict

Yes: `nix-router-optimized` should add a small, strictly isolated
`systemd-nspawn` HA lab first, and then treat proven `nspawn` scenarios as the
feeder path for later NixOS VM regression tests rather than as the end state of
validation.
