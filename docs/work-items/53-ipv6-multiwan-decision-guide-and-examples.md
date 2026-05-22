# 53 - IPv6 Multi-WAN Decision Guide and Examples

## Status: `ready`

## Objective

Create an explicit operator-facing decision guide for IPv6 multi-WAN so users can
choose among the repo's existing IPv6 tools without having to infer the intended
architecture from scattered module docs.

## Rationale

Round 125 converged that IPv6 multi-WAN should be presented as a **toolbox plus
decision ladder**, not as one magical feature.

The repo already has several relevant pieces:

- PvD / native multi-prefix support
- policy-routing hooks
- `router-nptv6`
- `ipv6Masquerade` / NAT66 escape hatch

But the right answer depends on operator constraints:

- client PvD support
- stable internal prefix needs
- upstream prefix churn
- whether translation is acceptable

Without a decision guide, users are likely to choose NAT66 too early or assume
PvD/NPTv6 are interchangeable.

## Requirements

- [ ] Add a dedicated IPv6 multi-WAN guide that helps operators decide among:
      - PvD / native multi-prefix
      - source-aware policy routing
      - NPTv6
      - NAT66 as last resort
- [ ] Include at least one realistic example for each recommended pattern
- [ ] Make the ordering and recommendation strength explicit:
      - preferred
      - advanced
      - discouraged / escape hatch
- [ ] Document the major client and operator tradeoffs, including:
      - client support variance for PvD
      - stable-inside benefits of NPTv6
      - source-address correctness constraints
      - why NAT66 is usually not the first recommendation

## Verification

- [ ] A user can answer “which IPv6 multi-WAN pattern should I use?” without
      reading module source
- [ ] The docs clearly distinguish native multi-prefix from translation-based
      approaches
- [ ] NAT66 is documented honestly as compatibility-oriented, not as the
      preferred architecture

## Notes

This is primarily a **docs / examples / operator-guidance** item.

It should not absorb large implementation changes to PvD, NPTv6, or policy
routing themselves unless a small docs-blocking fix is required.
