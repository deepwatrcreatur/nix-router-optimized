# Discussion 12: Borrowing from `phpIPAM` for Router Dashboard Inventory Browsing

**Status:** closed
**Opened:** 2026-05-21
**Participants requested:** protocol/networking panel, implementation panel, product/DX panel, GitHub Copilot

## Why this follow-up exists

Discussion 11 already settled the larger authority question:

- `phpIPAM` should not become the source of truth
- the repo-native declarative inventory should remain authoritative
- a read-only browse layer was the only narrow opening left on the table

Since then, `router-dashboard` has become a more substantial operator surface.
It now exposes runtime pages for:

- interfaces
- DHCP leases
- DNS
- tunnels
- remote admin
- VPNs
- NAT64
- firewall and system state

That makes the remaining question narrower and more concrete:

- is this now a good time to add first-class inventory browsing to the dashboard
- and if so, should the project borrow actual `phpIPAM` code or only borrow
  concepts

## Relevant prior context

From [`11-phpipam-vs-repo-native-host-inventory.md`](./11-phpipam-vs-repo-native-host-inventory.md):

- `phpIPAM` was rejected as a new authority model
- the panel agreed its strongest local value would only be browse/query
  convenience
- the strongest alternative was better repo-native generated views

From the current router dashboard:

- `modules/router-dashboard.nix` already exports a page-oriented dashboard shell
- `modules/router-dashboard/api/server.py` already serves runtime JSON for DHCP,
  DNS, interfaces, tunnels, and related status
- there is not yet a dedicated inventory-browser page centered on host/IP/subnet
  lookup and reduction of declarative inventory plus live runtime state

From public `phpIPAM` grounding gathered for this round:

- it presents itself as an open-source IPAM with:
  - visual subnet display
  - IP database search
  - subnet scanning / IP status checks
  - device management
  - VLAN / VRF views
  - REST API
- it is licensed under **GPLv3**

## Question for this discussion

Is this a good time to borrow from `phpIPAM` and enhance inventory browsing in
`router-dashboard`?

More concretely:

1. Is now the right time to improve inventory browsing in the dashboard?
2. Should the project borrow literal `phpIPAM` code, or only concepts and UI
   patterns?
3. How much does GPLv3 licensing change the code-reuse answer?
4. What is the best first slice if the project wants a read-only inventory
   browser without creating a second mutable authority?
5. Should the result be a widget, a new dashboard page, a generated view, or
   some combination?
6. If the answer is yes, what work items should follow?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **Gemini CLI:** substantive
- **Claude CLI:** substantive
- **DeepSeek API:** substantive
- **GitHub Copilot:** substantive

This round is therefore recorded as a **full roster**.

## Voice summaries

### Codex CLI

- Strongest on the claim that the usability gap is now concrete because
  `router-dashboard` already acts like a real local control plane but still lacks
  a first-class inventory-browser surface.
- Treated `phpIPAM`'s strongest value here as browse ergonomics:
  - subnet views
  - host/IP search
  - status summaries
- Rejected literal code borrowing as the wrong maintenance trade even before
  licensing:
  `router-dashboard` is a small local dashboard, while `phpIPAM` is a much
  larger application model.
- Treated GPLv3 as a material reason not to copy actual code.
- Preferred a new `Inventory` page over a widget.
- Proposed follow-ons around:
  - normalized inventory API data
  - read-only inventory page
  - consistency / reduction rules

### Gemini CLI

- Most explicit that GPLv3 is a hard stop on literal code reuse in practice.
- Strongest on borrowing **interaction patterns** instead:
  - subnet tree
  - utilization bars
  - search-across-objects
  - scan/status indicators
- Treated the missing need as a bounded one-page browsing problem, not a reason
  to import an entire IPAM runtime.
- Strongest implementation suggestion:
  generate a read-only JSON artifact from the declarative inventory and render it
  as a dedicated page.
- Preferred an intentionally small first slice:
  subnet-grouped host/IP list plus search, with denser visual subnet summaries as
  a later follow-on if the base page proves useful.

### Claude CLI

- Strongest on the “intent vs reality” operator value:
  the browser should help answer which hosts/IPs are declared, which are live,
  and where the gaps/conflicts are.
- Framed literal code borrowing as both a stack mismatch and a licensing burden:
  PHP/MySQL/GPLv3 is the wrong substrate for this dashboard.
- Treated a read-only inventory explorer as the right boundary:
  - no write path
  - no second authority
  - repo-native data remains canonical
- Proposed a useful first overlay:
  declared inventory plus active DHCP/lease state for reconciliation.

### DeepSeek API

- Strongest on the practical operator pain:
  `router-dashboard` already surfaces runtime state, but not a unified host/IP/
  subnet browse layer.
- Agreed that the previous discussion's “narrow opening” is now justified because
  the dashboard surface exists and can absorb a dedicated inventory page cleanly.
- Rejected literal `phpIPAM` code reuse because GPLv3 would materially change the
  reuse story and because importing code from a database-first IPAM into a
  repo-native router dashboard is structurally awkward.
- Favored a new dashboard page rather than an overview widget.
- Recommended:
  - canonical exported inventory data
  - read-only inventory API
  - inventory browser page with search and status badges

### GitHub Copilot

- I agreed that the project has reached the right maturity point for a
  repo-native inventory browser:
  the dashboard is now substantial enough that the missing browse layer is a real
  UX gap rather than a hypothetical desire.
- I also agreed with the stronger licensing and architecture boundary:
  **borrow ideas, not code**.
- My strongest synthesis point was that the right value here is not “IPAM
  management,” but a **read-only operator lens** over:
  - declared inventory
  - live DHCP leases
  - DNS names
  - and simple provenance/conflict states

## First-pass convergence

The obtained voices converged strongly on the following points.

1. **Yes, now is a good time to improve inventory browsing in `router-dashboard`.**
   The project now has enough dashboard surface area that the missing inventory
   browser is a concrete operator gap.

2. **No, this is not a good time to borrow literal `phpIPAM` code.**
   The panel rejected real code borrowing on both:
   - architectural grounds
   - and licensing grounds

3. **GPLv3 changes the answer materially.**
   The panel did not treat licensing as a minor footnote. Literal code reuse
   would create derivative-work obligations and is not the clean path here.

4. **The strongest thing to borrow from `phpIPAM` is browse design vocabulary, not
   implementation.**
   Specifically:
   - subnet hierarchy
   - status coloring
   - host/IP search
   - utilization / occupancy summaries
   - and operator-friendly “what lives where?” navigation

5. **The first slice should be read-only and repo-native.**
   The browser should reduce existing declarative inventory and runtime facts into
   a single searchable model. It should not create a second editable state
   surface.

6. **A dedicated dashboard page is the right UI boundary.**
   The panel strongly preferred a real inventory page over trying to compress this
   into a small widget.

## Real disagreements that remained

There was no major strategic disagreement.

The only meaningful differences were about the exact size of the first slice:

- **Gemini** preferred an extremely small first slice built from generated JSON
- **Claude** and **Copilot** emphasized a stronger declared-vs-live
  reconciliation view
- **Codex** and **DeepSeek** were comfortable naming a slightly richer API/data
  contract immediately

This was a difference in planning granularity, not direction.

## Final synthesis

The strongest answer from this round is:

**Improve inventory browsing now, but do it natively.**

The project has reached the point where a repo-native inventory browser is worth
building:

- the dashboard is already real
- the authority model is already clear
- and the remaining browsing pain is no longer hypothetical

But the round treated literal `phpIPAM` code borrowing as the wrong move.
`phpIPAM` is still useful here as:

- a source of UI inspiration
- a reminder that subnet and host browsing matters
- and a reference for what operators expect from an inventory browser

It is **not** the right codebase to import into this project.

The right next move is therefore:

- keep the repo-native declarative inventory as the single source of truth
- export a read-only normalized inventory model
- add a dedicated inventory page to `router-dashboard`
- and overlay simple live-state reconciliation instead of inventing a second
  mutable IPAM

## One-sentence verdict

Yes to a repo-native inventory browser in `router-dashboard`; no to borrowing
`phpIPAM` code; borrow its browse patterns, not its implementation or authority
model.
