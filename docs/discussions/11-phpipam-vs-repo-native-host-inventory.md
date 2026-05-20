# Discussion 11: Whether `phpIPAM` Should Organize IP-to-Host Inventory

**Status:** closed
**Opened:** 2026-05-19
**Participants requested:** inventory/source-of-truth panel, implementation panel, operator-UX panel, GitHub Copilot

## Why this discussion belongs here

This is not a router feature-module question in the narrow sense.

It still belongs in `nix-router-optimized` because the project's operational
story depends on having a clear authority boundary for:

- host IP assignments
- router-adjacent infrastructure metadata
- DHCP reservations
- DNS naming
- and the broader homelab inventory that router modules and docs assume

The maintainer wanted a discussion round on whether `phpIPAM` would be a good
fit for organizing IP-address-to-host mappings.

In other words: should the operational inventory around the router ecosystem
move toward a dedicated IPAM product, or should the current repo-native
authority model remain the center of gravity?

## Relevant prior context

From the existing homelab/source-of-truth setup used to ground the round:

- `unified-nix-configuration/lib/hosts.nix` already declares itself the
  authority and single source of truth for homelab host metadata
- that authority already spans more than bare IP allocation:
  - host IPs
  - SSH access metadata
  - DNS names and aliases
  - DHCP reservations
  - ingress labels
  - DDNS labels
- `unified-nix-configuration/outputs/checks.nix` already enforces alignment and
  duplicate-IP checks across that model
- some overlap still exists in Ansible inventory, so there is already real
  duplication pressure to manage carefully

That means the practical question is not "is phpIPAM a respectable tool?" but:

- does it solve a missing problem here
- or does it mostly introduce a second mutable authority that can drift from the
  repo-native source of truth

## Grounding used for this discussion

Public phpIPAM facts gathered before the round:

- phpIPAM presents itself as a free/open-source IP address management tool
- it provides subnet/IP management, VLAN/VRF support, device tracking, custom
  fields, scan/status features, and REST API access
- it is a mature long-running PHP/MySQL-style web application
- it therefore brings its own mutable database, web UI, and operational surface

Local architectural facts used in the round:

- the current repo-native model already behaves like an IPAM in practice
- the strongest missing capability is not authority, but easier browsing and
  human-friendly inventory views

## Question for this discussion

Should this project ecosystem adopt `phpIPAM` for organizing IP-address-to-host
inventory?

More concretely:

1. Does phpIPAM solve a real missing problem in the current setup?
2. Would it strengthen or weaken the existing source-of-truth boundary?
3. Is the right role, if any:
   - new authority
   - read/write sync peer
   - read-only mirror
   - or no adoption at all
4. If the real pain is usability, should the project instead generate better
   repo-native reports or browse surfaces?

## Participation record

What actually happened in this run:

- **Codex CLI:** substantive
- **Gemini CLI:** substantive
- **Claude CLI:** substantive
- **DeepSeek API:** substantive
- **OpenCode free-model enrichment:** substantive
- **GitHub Copilot:** substantive

This was a full real round. No missing seat was simulated.

## Voice summaries

### Codex CLI

- Strongest on the distinction between:
  - **authority**
  - and **operator convenience**
- Treated phpIPAM as potentially useful for:
  - subnet-centric browsing
  - utilization visibility
  - scan/status views
  - and multi-user interactive workflows
- But concluded that in the current setup it would mostly create drift risk by
  cutting across an already explicit source-of-truth boundary.
- Recommended:
  - do not adopt phpIPAM as authority
  - improve repo-native browsing and generation instead

### Gemini CLI

- Most willing to name a small real gap:
  - visual subnet maps
  - quick UI queries
  - easier browsing for less technical operators
- Even so, concluded that the repo already functions as the IPAM in practice.
- Treated phpIPAM as a poor fit because it would introduce:
  - another mutable system
  - extra operational overhead
  - and sync burden for limited gain

### Claude CLI

- Most explicit that phpIPAM would mainly create a **second authority that can
  drift**.
- Argued that phpIPAM's strongest features are better matched to larger
  multi-user teams with delegated workflows, not this current single-maintainer
  homelab setup.
- Recommended:
  - do not adopt phpIPAM
  - generate lightweight inventory views directly from the repo-native source

### DeepSeek API

- Most direct that phpIPAM solves **no missing authority problem** here.
- Emphasized that:
  - the current repo already has an integrated authority model
  - phpIPAM would add operational overhead
  - and the likely result is drift between the web app and the repo
- Recommended:
  - do not adopt phpIPAM in the current context

### OpenCode free-model enrichment

- Reinforced the same overall conclusion.
- Recognized that phpIPAM offers a friendlier browsing surface, but still judged
  that the cost and drift risk outweigh the benefit here.
- The seat's own satisfaction marker was negative, but the actual substance still
  converged with the rest of the panel: do not adopt phpIPAM for this homelab
  workflow.

### GitHub Copilot

- I agreed with the panel's main boundary:
  - the repo-native inventory model is already the authority surface
  - phpIPAM is not filling a missing authority role
  - its strongest possible value would only be UI/query convenience
- My strongest synthesis point was that the better next move is lighter
  repo-native views and generation, not a new database-backed inventory system.

## First-pass convergence

The panel converged on the following points.

1. **phpIPAM should not become the new source of truth.**
   No substantive voice supported replacing the repo-native authority model with
   phpIPAM.

2. **The current repo-native model already behaves like an IPAM.**
   The current host/inventory source of truth plus downstream checks already
   covers the core IP-to-host mapping problem in a declarative, reviewable way.

3. **The strongest phpIPAM value here would only be browsing convenience.**
   The real advantages identified were:
   - visual subnet browsing
   - ad-hoc querying
   - scan/status views
   - and potential multi-user workflows

4. **For this current setup, those advantages do not outweigh drift and
   operational cost.**
   The recurring risks were:
   - second mutable authority
   - sync complexity
   - narrower data model than the existing repo-native authority
   - and extra application/database maintenance

5. **If the real pain is readability, the better answer is repo-native views.**
   The repeated alternative was to generate:
   - HTML/JSON/CSV views
   - subnet utilization reports
   - search/query helpers
   - or tighter inventory generation/validation
   from the existing source of truth

## Real disagreements that remained

There was only a narrow disagreement about whether phpIPAM might still be worth
trying later as a non-authoritative convenience layer.

- Codex allowed that a **read-only mirror fed from the repo** could be
  defensible later if there were a concrete browsing/UI need
- Gemini also left room for UI-oriented value
- Claude and DeepSeek were more conservative and preferred not adopting it at
  all in the current context

No substantive voice recommended a read/write adjunct or a new database-backed
authority.

## Final synthesis

The strongest answer from this discussion is:

- keep the repo-native host/inventory model as the single authority
- do **not** adopt phpIPAM as:
  - the new source of truth
  - or a read/write sync peer
- if inventory usability becomes painful, improve the current model by adding:
  - generated views
  - reports
  - query tooling
  - and tighter reduction of remaining duplicated inventory surfaces

Only if there is later a concrete need for a browsable web view should the
project even consider phpIPAM, and then only as a possible **read-only mirror**
generated from repo data, not as an editing authority.

## One-sentence verdict

`phpIPAM` is the wrong authority model for this repo ecosystem right now: keep
the inventory declarative and repo-native, and invest in better generated views
instead of adding a second mutable IPAM database.
