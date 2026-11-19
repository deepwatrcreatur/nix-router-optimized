# Incident: X520 TCP reply loss on elitedesk

**Status:** ACTIVE (diagnosis)
**Severity:** P2. It blocks failover: zone transfers and the HA SOA check use TCP.
**Opened:** 2026-11-19
**IC:** Claude
**Tracking:** nix-clan-homelab bead `nch-sny.34`

## Problem statement

1–8% of TCP connections from elitedesk (bare-metal standby, Intel X520
`enp1s0f1`) to router (10.10.10.1:53) time out. Router answers every SYN, but
for an affected connection elitedesk receives none of the SYN-ACKs, including
six or more retransmits over about 16 s. UDP from elitedesk and TCP from other
LAN hosts are unaffected.

## Verified facts

1. Router receives the SYN and sends the SYN-ACK out its LAN vNIC for every
   failed connection (E7).
2. elitedesk captures none of those SYN-ACKs on any interface (E7). No XDP or
   tc programs are attached (E10).
3. The loss sticks to one connection instance, not to a 4-tuple (E7, E8).
4. Router's listen-overflow counter belongs to router-dashboard :8888, not DNS
   (E5).
5. With Flow Director ATR disabled (`ntuple on`), 0 of 6920 TCP queries
   failed over 2 h, and `fdir_match` stayed flat (E11, E13). A short ATR-on
   control was clean (E12); a 2 h ATR-on control is running (E14).

## Navigation

- Data: [`RESEARCH_LEDGER.md`](RESEARCH_LEDGER.md)
- Positions: [`ACTIVE_DISCUSSION.md`](ACTIVE_DISCUSSION.md)
