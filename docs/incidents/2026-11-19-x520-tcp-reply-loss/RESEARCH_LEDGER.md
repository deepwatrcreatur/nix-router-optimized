# Research Ledger: X520 TCP reply loss on elitedesk

Raw probes and results. Positions and reasoning go in `ACTIVE_DISCUSSION.md`.
Homelab tracking bead: `nch-sny.34` (nix-clan-homelab).

## Topology and baseline

- **router**: the current primary, a Proxmox VM. LAN `enp6s16` is
  10.10.10.1/16 (MAC 02:76:c6:01:2a:af); management `ens18` is
  192.168.100.100/24. It runs Technitium DNS on 10.10.10.1:53 with a TCP
  listen backlog of 100.
- **elitedesk**: the standby, bare metal. The LAN NIC is an Intel
  82599ES/X520 port `enp1s0f1` on a DAC cable: 10.10.10.4/16, MAC
  90:e2:ba:7f:e0:3d, ixgbe on kernel 6.18.63, firmware 0x000161ab
  1.3082.0, loaded with `allow_unsupported_sfp=1`.
  - Management is the onboard `eno1`, 192.168.100.98/24.
  - The port has 8 combined queues, 4096-entry rings and `rx-usecs` 1 (set by
    router-optimizations), with GRO on, LRO off and no XDP or tc programs.
- **Shared L2:** broadcast frames arrive on both elitedesk NICs, and router has
  learned 10.10.10.4 on both of its NICs. LAN and management share an L2
  segment.
- **Earlier hardware event (bead `nch-sny.31`):** on 2026-11-18 at 17:13
  `ixgbe 0000:01:00.1` logged "Adapter removed" with FWSM 0xFFFFFFFF. A driver
  rebind and an FLR both failed, and a warm reboot recovered it.
- **Emerald** is a control client: the workstation, on the same LAN, with a
  different NIC.

## Hypotheses

| ID | Hypothesis | Confidence | Status |
| --- | --- | --- | --- |
| H0 | Router's Technitium TCP listen queue overflows | - | **Disproven** (E5) |
| H1 | X520 Flow Director ATR mis-steers or drops RX for some TCP flows on elitedesk | High | Open; supported by E9, E11 |
| H2 | L2 problem: switch MAC-table flapping or an ARP mix-up between the shared LAN and management segment | Low | Open; E6 weakens it |
| H3 | A filter that runs before tcpdump drops the packets (XDP, tc) | - | **Disproven** (E10) |
| H4 | Driver or firmware fault on this card, related to the PCIe dropout (`nch-sny.31`) | Medium | Open |
| H5 | Tuning in `router-optimizations` (rings, coalescing, offloads) triggers it | Low | Open |

## Experiments

| ID | Probe | Result | Interpretation |
| --- | --- | --- | --- |
| E1 | 20 TCP SOA queries, elitedesk → router, 2 s timeout | 1 failure | First sighting, during a zone-HA rehearsal |
| E2 | 10 min, 1 query/s, TCP and UDP, from elitedesk and emerald at once | elitedesk TCP 18/504 failed, UDP 0/504; emerald 0/1170 | Specific to TCP from elitedesk |
| E3 | Router `nstat` | ListenOverflows 142827, ListenDrops 143902 since boot, about 7/min | Looked like H0 |
| E4 | `ss` sampled every 10 ms during failures | the :53 queue never exceeded 1/100 | Contradicts H0 |
| E5 | bpftrace kprobe on `tcp_conn_request` for full accept queues during failures | only `lport=8888 q=5/5` (router-dashboard); never :53 | H0 disproven. The dashboard's backlog of 5 is a separate bug |
| E6 | ARP on both ends | elitedesk always uses router's LAN MAC; router answers 10.10.10.4 out `enp6s16` | No ARP flux on this path |
| E7 | Capture on router (any iface) and elitedesk (`-i any`) at once; 121 connections, 10 failed | Every failed connection: router got the SYN and sent SYN-ACK out `enp6s16` six or more times over about 16 s. elitedesk captured none of them on any interface. Connections opened in between succeeded | Replies lost between router's vNIC egress and elitedesk's capture point |
| E8 | Reused the 10 failed source ports, plus 4 controls, in two rounds 65 s apart | 28/28 succeeded | Not deterministic per 4-tuple; the loss is tied to a connection instance |
| E9 | ECN check | 13 of 14 `[SEW]` SYNs answered with `[S.E]`; the failures include plain-SYN retries | ECN is not the cause |
| E10 | XDP, tc and bpf attachments on `enp1s0f1` | none | H3 disproven |
| E11 | `ethtool -K enp1s0f1 ntuple on` (disables ATR), 400 TCP queries | 0/400; `fdir_match` stopped increasing | Supports H1 |
| E12 | Control: ntuple off (ATR back on), 400 queries; then ntuple on again, 400 queries | 0/400 and 0/400 | Inconclusive. Failures come in bursts, and the toggle may flush a stale Flow Director table |
| E13 | 2 h soak, ntuple on (ATR off), 1 TCP + 1 UDP query/s (07:50–09:50, unit `dns-soak-atr-off`) | 6920 TCP and 6920 UDP queries, **0 failures**. `fdir_match` frozen at 16875 for the whole run (`fdir_miss` 126100) | Strongly supports H1. At E2's 3.6% rate about 250 TCP failures were expected, and at least 69 even at 1% |
| E14 | Control: 2 h soak, ntuple off (ATR on) again, same probe (from 09:51, unit `dns-soak-atr-on`) | running | If failures return, H1 is confirmed |

## Counters

- Flow Director (`ethtool -S enp1s0f1`): `fdir_match` 14007 and `fdir_miss`
  55326 before E11; `fdir_overflow` 0.
- `rx_dropped` grows by a few per minute. This counts stack drops, not
  hardware loss: `rx_missed_errors`, `rx_no_dma_resources` and
  `rx_crc_errors` are all 0.
- All 8 RX queues had packets (`rx_queue_0` through `rx_queue_7`).
