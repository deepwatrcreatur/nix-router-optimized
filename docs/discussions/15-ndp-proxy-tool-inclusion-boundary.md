# Discussion 15: Whether to Add `ndppd`, `ndpresponder`, `ndproxy`, and `ndp-proxy-go` as Flake Options

**Status:** closed
**Opened:** 2026-05-29
**Participants requested:** Codex CLI, GitHub Copilot CLI, Claude CLI, and one GPT-5.4 mini seat

## Why this discussion belongs here

This is not just a packaging question.
It is a support-boundary and recovery-boundary question for a Linux/NixOS router
flake that tries to stay honest about what it really supports.

The maintainer asked whether flake consumers should be offered these NDP-related
choices directly:

- `ndppd`
- `ndpresponder`
- `ndproxy`
- `ndp-proxy-go`

That sounds like a simple feature-surface request, but it carries real implied
promises about:

- Linux vs. FreeBSD platform fit
- nixpkgs packaging and maintenance burden
- HA and failover correctness
- whether these tools are actually interchangeable
- and whether the repo wants to be a narrowly supported router flake or a broad
  NDP-proxy toolbox

## Grounding used for this discussion

The following facts grounded the round.

- `ndppd` is a Linux NDP proxy daemon already available in nixpkgs.
- `ndpresponder` is a Go responder with real KVM/cloud routed-prefix use cases,
  but it is not currently in nixpkgs.
- `ndp-proxy-go` is explicitly shaped around a FreeBSD router story and bundles
  RA/NDP/route behavior in a way that does not map cleanly onto the repo's
  Linux/NixOS surface.
- `ndproxy` is not one clean upstream target in this context; the name is used
  for multiple unrelated or loosely maintained implementations.
- `systemd-networkd` already has a bounded native static-address path via
  `IPv6ProxyNDP=` and `IPv6ProxyNDPAddress=`. That matters because a daemon is
  not the only answer for every case.
- The repo's current HA posture already treats single-active ownership as a real
  support boundary in adjacent modules such as BGP.

## Question for this discussion

Should `nix-router-optimized` add these tools as flake-consumer options?

More concretely:

1. Should all four be offered, or only a subset?
2. Which of them actually fit a Linux/NixOS router flake?
3. Should the repo expose raw per-tool wrappers or one normalized NDP-proxy
   module surface?
4. What does HA correctness require before any such module is supportable?
5. What judgment should be recorded in the local discussion archive?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **GitHub Copilot CLI:** substantive
- **Claude CLI:** substantive
- **GPT-5.4 mini seat:** substantive

This was a small but real multi-seat round.
The voices were narrower than the repo's largest discussion rosters, but they
were enough to test the support-boundary question from multiple angles.

## Voice summaries

### Codex CLI

- Most open to **selective inclusion** rather than a blanket no.
- Strongest on the idea that consumers do hit real IPv6 routed-prefix and
  VPS/KVM topologies where first-class NDP proxying is useful.
- Judged `ndppd` the best near-term supported option.
- Was more open than the others to treating `ndpresponder` as an
  experimental/unsupported backend later, if exposed clearly and without
  pretending it is already inside the normal support contract.
- Rejected `ndproxy` and `ndp-proxy-go` as normal flake options.

### GitHub Copilot CLI

- Strongest on the **integration-cost and support-honesty** angle.
- Argued that the real near-term candidate is at most one advanced opt-in
  module, wrapping `ndppd` behind an intent-level interface such as
  `services.router-ndp-proxy`.
- Most explicit that HA is not optional glue work here:
  the module would need a hard assertion parallel to the BGP module's
  `ha.singleActiveOwner` gate so the repo does not silently bless dual-active
  NDP replies during failover.
- Also emphasized that the docs should explicitly point users toward the
  `systemd-networkd` static-address path before steering them into a daemon.
- Treated `ndpresponder` as a real tool with real cloud use cases, but deferred
  it until it exists in nixpkgs or the repo explicitly decides to own its
  packaging burden.

### Claude CLI

- Strongest on the trust cost of exposing too many options too early.
- Framed the central risk as: once a router flake presents four knobs, users
  reasonably assume those knobs are tested, supported, and part of the project's
  recovery story.
- Favored shipping `ndppd` now as the only cleanly scoped option because it is
  Linux-native, already in nixpkgs, and close to the existing project surface.
- Wanted everything else held back until there is a sharply defined Linux use
  case that does not expand on-call maintenance debt.
- Rejected `ndproxy` as too ambiguous and `ndp-proxy-go` as the wrong platform
  story for this repo.

### GPT-5.4 mini seat

- Strongest on the “do not imply interchangeability” point.
- Agreed that `ndppd` is the only tool that currently looks like a stable
  consumer-facing option for this repo.
- Treated `ndpresponder` as plausible only after packaging and explicit
  experimental labeling are in place.
- Rejected `ndproxy` and `ndp-proxy-go` as first-class consumer options.
- Preferred a small backend selector over a broad family of separate module
  namespaces.

## First-pass convergence

The panel converged on the following points.

1. **Do not expose all four tools as equal flake options.**
   No seat supported turning this into a broad NDP toolbox surface.

2. **`ndppd` is the only clear near-term candidate.**
   The reasons repeated across the panel were:
   - Linux-native fit
   - already in nixpkgs
   - bounded implementation surface
   - and a support cost that is real but understandable

3. **`ndpresponder` is real, but deferred.**
   The panel did not dismiss it as useless.
   It was repeatedly recognized as relevant for routed-prefix, VPS, and KVM
   cases.
   The blocker is not concept alone; it is that the repo would have to own extra
   packaging and support burden before the tool crosses into the same class as
   `ndppd`.

4. **`ndproxy` and `ndp-proxy-go` are out of scope for the current flake
   boundary.**
   The reasons differed slightly:
   - `ndproxy` is too fragmented and ambiguous
   - `ndp-proxy-go` belongs to a FreeBSD-centered architecture story rather than
     the repo's Linux/NixOS router surface

5. **The interface should be normalized, not tool-shaped.**
   The panel strongly preferred one higher-level NDP proxy module surface over
   multiple raw per-tool namespaces.
   That keeps the consumer contract centered on intent rather than daemon
   branding.

6. **HA correctness must be explicit before shipping.**
   The discussion converged that any NDP proxy module would need a single-active
   ownership rule, not just a best-effort note in docs.
   In practical repo terms, that means the same style of assertion already used
   in adjacent HA-sensitive modules:
   the repo should not silently allow both router nodes to answer for the same
   proxied addresses.

7. **Docs must clearly separate static and dynamic cases.**
   The round repeatedly treated it as important that operators first learn when
   `systemd-networkd` static `IPv6ProxyNDP` entries are sufficient, and only use
   an NDP daemon when they truly need dynamic neighbor handling.

## Real disagreements that remained

There was no major disagreement on the bottom line.

The only meaningful difference was **how close `ndpresponder` is to inclusion**.

- **Codex** was somewhat more open to reserving an experimental backend path for
  it sooner, as long as the support tier stayed explicit.
- **Copilot**, **Claude**, and the **mini seat** were more conservative and
  preferred to keep it out of the flake boundary until nixpkgs packaging or a
  deliberate repo-side packaging commitment exists.

That is a disagreement about timing and maintenance appetite, not about whether
`ndpresponder` is a real tool.

## Final synthesis

The strongest archived answer from this discussion is:

- do **not** add `ndppd`, `ndpresponder`, `ndproxy`, and `ndp-proxy-go` as a
  broad menu of equal consumer-facing options
- if the repo moves on this area, the honest near-term move is a **single,
  advanced opt-in NDP proxy module** centered on `ndppd`
- document the native `systemd-networkd` static proxy path first so operators do
  not reach for a daemon unnecessarily
- require an explicit HA/single-active-owner assertion before any module is
  treated as supported
- track `ndpresponder` as a later candidate rather than pretending it is already
  inside the flake's normal support contract
- and exclude `ndproxy` plus `ndp-proxy-go` from the present Linux/NixOS flake
  boundary

In other words, the correct line is not “support everything NDP-related.”
It is “answer the real Linux router need with one bounded, supportable surface,
then expand only if the maintenance contract becomes equally clear.”

## One-sentence verdict

`nix-router-optimized` should **not** expose all four NDP tools as peer flake
options; the only honest near-term path is an advanced opt-in `ndppd`-based
module with explicit HA ownership rules, while `ndpresponder` stays deferred and
`ndproxy` / `ndp-proxy-go` stay out of scope.
