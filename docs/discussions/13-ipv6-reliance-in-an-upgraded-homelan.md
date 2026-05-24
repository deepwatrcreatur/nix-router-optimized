# Discussion 13: Whether an Upgraded Homelan Should Lean More on IPv6

**Status:** closed
**Opened:** 2026-05-23
**Participants requested:** Codex CLI, GitHub Copilot CLI, Gemini CLI, DeepSeek API, and one OpenCode free-model seat

## Why this follow-up exists

The recent router recovery changed the practical question.

- DHCP/DDNS is healthy again
- `ipad.deepwatercreature.com` now resolves and tracks a fresh lease correctly
- forward and reverse publication work again
- and name-based access is more real than it was before the recovery

That naturally raises a narrower operational question:

- now that the router capability is stronger and hosts can increasingly be reached
  by name, is there something real to gain by leaning harder on IPv6 inside the
  homelan?

But the environment is still not greenfield.

- some Proxmox hosts were installed around static IPv4 assumptions
- the network still has mixed legacy and infrastructure realities
- and shortname resolution is still incomplete in practice:
  `ipad.deepwatercreature.com` works, but `ping ipad` still fails

So this round is not asking whether IPv6 is theoretically superior.
It is asking whether the current homelan should actually change its operating
habits now.

## Relevant prior context

From [`01-ipv6-vpn-redirection.md`](./01-ipv6-vpn-redirection.md):

- the repo already treats pragmatic IPv6 tooling as in scope
- especially when it solves real operator problems rather than chasing purity

From [`02-ipv6-redirection-standards-vs-pragmatism.md`](./02-ipv6-redirection-standards-vs-pragmatism.md):

- the project already rejected a purity-first posture for hostile or mixed
  environments
- and defended bounded pragmatic tools when they improve real networking outcomes

From the current repo surface:

- `README.md` already presents:
  - NAT64
  - DNS64
  - and an experimental CLAT-style first slice
- `tests/router-kea-eval.nix` explicitly checks that `router-kea` advertises:
  - DHCP option 15 `domain-name`
  - DHCP option 119 `domain-search`

That means the current shortname gap is not evidence that the repo rejects local
name ergonomics. It is evidence that live deployment and client resolver behavior
still matter even when the declarative boundary is already present.

## Question for this discussion

Is there meaningful practical value in relying more on IPv6 inside this homelan
now that router naming and DDNS behavior are healthier?

More concretely:

1. Is there real operator value in shifting this homelan toward more IPv6
   reliance now?
2. If yes, what should become more IPv6-centric, and what should remain IPv4 or
   dual-stack for the foreseeable future?
3. How much does the current shortname-resolution failure weaken the case for
   “use names instead of remembering IPv4 addresses”?
4. How should the Proxmox/static-IPv4 constraint shape the migration boundary?
5. What concrete discussion-board recommendation should be recorded:
   - stay ordinary dual-stack
   - move to IPv6-first naming
   - pursue IPv6-mostly only on selected segments
   - or something else?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **GitHub Copilot CLI:** substantive
- **Gemini CLI:** substantive
  - emitted a keychain warning and fell back to file-backed credential storage
  - still returned a usable answer body
- **DeepSeek API:** substantive
  - run through the real DeepSeek HTTPS API using the local decrypted key and an
    explicit CA bundle
- **OpenCode free-model seat:** substantive via `opencode/nemotron-3-super-free`

This round is therefore recorded as a **full requested roster** with one real
free-model seat included as requested rather than merely simulated.

## Voice summaries

### Codex CLI

- Strongest on the claim that the gain is **bounded rather than transformative**:
  the main value is reducing dependence on remembered IPv4 literals where IPv6
  and FQDN-based access already work cleanly.
- Recommended:
  - IPv6-preferred for consumption and selected new segments
  - dual-stack or IPv4-stable infrastructure for Proxmox and other static
    operational islands
- Treated shortname failure as a meaningful but partial blocker:
  FQDN naming is already useful, but not yet ergonomic enough to declare the
  naming problem solved.
- Final stance:
  keep the homelan broadly dual-stack and avoid a whole-LAN IPv6-first reframing.

### GitHub Copilot CLI

- Strongest on the repo-consistency point:
  `nix-router-optimized` already treats IPv6-mostly as a bounded opt-in pattern,
  not the default answer for every ordinary LAN.
- Treated the current value as **incremental**:
  - better FQDN-based access
  - more natural IPv6 use where clients already handle it well
  - and a cleaner path for selected new segments
- Most explicit that fixing shortname/search-domain behavior is a higher-priority
  operator win than “pushing harder on IPv6” in the abstract.
- Recommended:
  stay broadly dual-stack, prefer FQDNs and IPv6 where already solid, and limit
  IPv6-mostly experiments to non-core segments.

### Gemini CLI

- Strongest on the dogfooding argument:
  leaning into IPv6 on client and transient segments is useful partly because it
  exercises the repo’s NAT64/DNS64/CLAT direction in a real homelan rather than
  leaving those paths underused.
- Drew the sharpest infrastructure boundary:
  - Proxmox and core management remain the static dual-stack safety net
  - aggressive IPv6-first experiments should happen north of that boundary
- Treated shortname failure as a **significant UX friction point** that blocks
  real operator adoption more than it blocks protocol correctness.
- Preferred:
  IPv6-mostly on client/transient segments only, not on the management plane.

### DeepSeek API

- Strongest on the claim that the value is real but mostly about
  **operational convenience**, not necessity:
  - less NAT awkwardness
  - cleaner inbound service patterns
  - and better long-term posture for modern clients
- Split the environment most explicitly into:
  - IPv6-centric new clients and some new service endpoints
  - dual-stack Proxmox/static infrastructure
  - and IPv4-only legacy devices that are not worth forcing across the line
- Treated shortname failure as a targeted deployment/resolver problem, not a
  reason to abandon naming.
- Recommended:
  selected-segment IPv6-mostly with infrastructure kept dual-stack and
  IPv4-primary where needed.

### OpenCode free-model seat (`opencode/nemotron-3-super-free`)

- Most aggressive on the end-to-end benefits of IPv6:
  - less NAT complexity
  - simpler troubleshooting
  - and stronger encouragement to publish/use AAAA where available
- Strongest on the phrase **IPv6-first naming**:
  use names and AAAA records more deliberately while retaining dual-stack for
  Proxmox and other legacy-bound hosts.
- Still accepted the same hard boundary:
  Proxmox/static-IPv4 hosts remain anchors rather than immediate migration
  targets.
- Treated shortname failure as a fixable ergonomics gap via search-domain or
  similar name-resolution improvements.

## First-pass convergence

The obtained voices converged strongly on the following points.

1. **Yes, there is something to gain from more IPv6 reliance now, but the gain is
   bounded and incremental.**
   The panel did not treat this as a reason for a whole-homelan IPv6-first
   redesign. The gain is mainly:
   - better day-to-day name-based access
   - more natural IPv6 use on modern clients
   - and a cleaner platform for selected new segments/services

2. **Core infrastructure should remain dual-stack or explicitly IPv4-stable for
   now.**
   There was strong agreement that:
   - Proxmox
   - static-infra hosts
   - management paths
   - and other break-glass systems
   should not be treated like greenfield IPv6-migration targets.

3. **Client, guest, and transient segments are the best place to lean further
   into IPv6.**
   Multiple voices converged on the same boundary:
   - phones
   - tablets
   - laptops
   - guest/edge segments
   - and fresh VM/container workloads
   are the most reasonable places for IPv6-preferred or IPv6-mostly operation.

4. **The shortname failure materially weakens ergonomics, but does not negate the
   value of FQDN-based naming.**
   The panel strongly agreed that:
   - `ipad.deepwatercreature.com` working is already real operational progress
   - but `ping ipad` failing means “just use names” is not yet ergonomic enough
     to replace address habits completely

5. **Shortname/search-domain repair is a high-value next improvement regardless of
   broader IPv6 posture.**
   This was one of the strongest practical convergences in the round.
   The panel repeatedly treated shortname repair as:
   - a smaller
   - more immediate
   - and more operator-visible win
   than a larger abstract push toward IPv6 everywhere.

6. **The strongest overall recommendation is pragmatic dual-stack with selective
   IPv6 deepening.**
   The convergence was not “stay exactly where you are forever.”
   It was:
   - keep the homelan broadly dual-stack
   - encourage FQDN-first / IPv6-preferred habits where they already work
   - and use selected client/transient segments as the place to push further

## Real disagreements that remained

There was no major strategic disagreement.

The meaningful differences were about **how aggressively** to lean in.

- **Codex** and **GitHub Copilot CLI** were the most conservative:
  stay broadly dual-stack and treat IPv6 deepening as selected-segment behavior
  rather than a top-level homelan identity change
- **Gemini** was somewhat more willing to use selected client/transient segments
  as deliberate dogfood for the repo’s NAT64/DNS64/CLAT direction
- **DeepSeek** sat in the middle:
  practical benefit is real, but still not strong enough to justify disturbing
  static-infra foundations
- **OpenCode** was the most forward-leaning on IPv6-first naming and on using new
  internal services as IPv6-centric candidates, while still accepting the same
  hard Proxmox/legacy boundary

This was a difference in migration aggressiveness, not direction.

## Final synthesis

The strongest answer from this round is:

**Yes, the upgraded router capability creates a real opportunity to rely a bit
more on IPv6 and names, but not to redefine the whole homelan as IPv6-first.**

The repaired DHCP/DDNS path means the network is now in a better position to
benefit from:

- FQDN-first access habits
- more natural IPv6 use on modern clients
- and selective IPv6-mostly operation on non-core segments

But the round treated two boundaries as decisive:

1. **Proxmox and other static-infrastructure islands remain the operational
   anchor.**
   They should stay dual-stack or IPv4-stable for now.

2. **Shortname ergonomics are still incomplete.**
   The repo already has a declarative path for search-domain advertisement, but
   the live/user-visible shortname story is still incomplete enough that “just
   use names” cannot yet be treated as a fully solved operational answer.

That leads to a pragmatic recommendation:

- keep the homelan broadly dual-stack
- treat FQDN-based access as the current naming default
- repair shortname/search-domain behavior as a worthwhile near-term operator fix
- and push IPv6 further mainly on:
  - client segments
  - guest/transient networks
  - and fresh workloads that do not inherit old static-IPv4 assumptions

The round did **not** support:

- a whole-homelan IPv6-first migration
- trying to force Proxmox/core management away from IPv4 stability
- or pretending that working FQDNs automatically mean all naming ergonomics are
  already done

## One-sentence verdict

Lean further into IPv6 and names at the homelan edge, but keep the core
pragmatically dual-stack and treat shortname/search-domain repair as the next
high-value step before claiming that names have fully replaced IPv4 habits.
