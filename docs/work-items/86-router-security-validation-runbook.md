# 86 - Router Security Validation Runbook

## Status: `ready`

## Objective

Add a repo-local operator runbook that validates the running router from three
viewpoints:

- router-local
- LAN-side
- and WAN-side

so operators can tell whether a change left the live router in the intended
security posture instead of relying on module configuration alone.

Suggested branch: `docs/router-security-validation-runbook`

## Rationale

Discussion 16 concluded that `nix-router-optimized` already exceeds
`francis-io/OpenBSD-Ansible-Router` on capability, but still lacks one of its
cleanest operational artifacts:

- an explicit post-change security-validation runbook

The local repo has:

- `router-security-hardened`
- firewall and HA docs
- dashboard and `router-diag`

but it does not yet have a single operator-facing document that says:

- what to check on the router itself
- what to check from another LAN host
- what to check from outside the WAN path
- what findings are expected
- and what findings should be treated as stop-and-investigate evidence

This matters more here than in the OpenBSD repo because this router can
intentionally expose more features and therefore has more ways to drift into an
unsafe or confusing state.

## Requirements

- [ ] Add `docs/router-security-validation.md`
- [ ] Cover at least three validation viewpoints:
      - router-local
      - LAN-side
      - WAN-side
- [ ] Include concrete commands appropriate to the local stack, such as:
      - `nft list ruleset`
      - `ss -tulpen` or equivalent listener inspection
      - `systemctl` checks for key services
      - `ip route` / `ip rule`
      - LAN-side `nmap` examples
      - WAN-side scan guidance
- [ ] Distinguish:
      - expected-open surfaces when specific optional features are enabled
      - and findings that should not appear unless intentionally configured
- [ ] Include a validation cadence, such as:
      - after first deployment
      - after firewall / DNS / DHCP / HA / WAN changes
      - after upstream modem or topology changes
      - and periodically for assurance
- [ ] Keep scan artifacts and real public IP values out of git
- [ ] Link the runbook from the most relevant existing docs

## Verification

- [ ] An operator can use the repo docs to determine whether a suspected outage
      is more likely:
      - DHCP
      - DNS
      - firewall / routing
      - or unexpected WAN exposure
- [ ] The repo has one clear security-validation reference instead of scattered
      implied steps
- [ ] The resulting doc is careful not to overclaim a single expected-open-port
      picture for all possible feature combinations

## Notes

This item is about **operator validation guidance**, not about introducing new
runtime services or changing firewall defaults.
