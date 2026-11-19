# Active Discussion: X520 TCP reply loss on elitedesk

Format: agent-roundtable blackboard with the satisfaction protocol. Each voice
appends one signed position (`Position A`, `B`, ...) and marks every question
`[satisfied]`, `[satisfied-conditional: X]` or `[needs more evidence: X]`.
Evidence lives in `RESEARCH_LEDGER.md`. Cite experiment IDs.

## Brief

See `SUMMARY.md` and `RESEARCH_LEDGER.md`. The router stack is
nix-router-optimized on NixOS 26.05. elitedesk is meant to become the primary
router, so its LAN NIC must be reliable before any failover.

## Questions

- **Q1. Root cause.** Given E1–E13, what is the most likely mechanism by which
  an established set of SYN-ACK retransmits for one TCP connection never
  reaches elitedesk's capture point, while other connections succeed in the
  same seconds and UDP is unaffected? Rank H1–H5 and add any we missed (for
  example the ATR signature-hash collision behaviour of the 82599, ixgbe
  version issues, the DAC or SFP under `allow_unsupported_sfp`, or switch
  behaviour).
- **Q2. Discriminating experiments.** Which tests, in order, would separate the
  remaining hypotheses with the least risk? Elitedesk is a standby and may be
  changed; router is live and may only be observed read-only. Name the
  counters or captures that would prove each one.
- **Q3. Fix.** If ATR is the cause, what is the right persistent fix in
  nix-router-optimized (`ntuple on`, an `ixgbe` module parameter, disabling
  ATR for router roles in general), and what are its costs? If it is not ATR,
  what then?
- **Q4. Hardware decision.** The same card also dropped off the PCIe bus once
  (`nch-sny.31`). The operator has a Mellanox ConnectX-4 available. When does
  the evidence justify replacing the X520, and what would the ConnectX-4 need
  (driver, flow steering defaults, SFP compatibility)?

## Positions
