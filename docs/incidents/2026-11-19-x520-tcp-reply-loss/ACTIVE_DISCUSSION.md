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

### Round 1 (2026-11-19, evidence E1–E13; full quorum)

#### Position A: Codex (`codex exec`, read-only)

**Q1 Root cause.** H1 > H4 > H2 > H5. The leading hypothesis is transient 82599 Flow Director signature steering. ixgbe ATR learns from outgoing TCP traffic, including sampled SYNs, so a SYN can establish steering state before its SYN-ACK arrives. Retransmits have the same reverse-flow signature and can repeatedly hit the same entry while other flows succeed and UDP is unaffected (E2, E7–E8). A signature collision could select the wrong RX queue, but steering to a healthy queue would still yield a capture. The missing step is whether the selected queue fails to deliver or another hardware or driver fault discards the frame. E11–E13 implicate the ATR-enabled configuration, but changing `ntuple` can also reset receive state, and E14 is pending. H4 could underlie H1 or be independent. The earlier `0xFFFFFFFF` register read suggests PCIe/device inaccessibility, with no demonstrated temporal link to these losses. H2 includes Proxmox bridge, physical uplink and switch forwarding. E6 weakens ARP flux, while E7 leaves those hops in scope. H5 could amplify a queue-specific fault. DAC or port faults rank lower given the TCP flow selectivity and zero CRC errors. E5 rules out DNS backlog overflow, E10 found no XDP or tc attachments on the X520 port, and E9 weakens ECN. — [satisfied-conditional: ATR is the leading trigger, while the exact drop mechanism is unverified]

**Q2 Discriminating experiments.**

1. Read E14 first. If clean, extend the ATR-on exposure across representative traffic and idle periods before toggling again. If loss recurs, repeat the same probe with ATR off, keeping query cadence and tuning fixed. H1 predicts recurrence with ATR on and suppression with it off. Log failed tuples, `fdir_match`, `fdir_miss`, `fdir_overflow`, per-queue packets and drops, `rx_missed_errors`, and `rx_no_dma_resources`. Aggregate Flow Director counters cannot identify a failed packet. Risk is brief standby interruption on feature changes.
2. During recurrence, correlate router vNIC egress, Proxmox bridge/uplink captures where available, switch egress toward elitedesk via an existing mirror or passive tap, and elitedesk capture. Match MAC, tuple and TCP sequence numbers. Frames reaching the last monitored link but missing from host capture favor NIC, driver or last-link loss. Frames disappearing upstream favor H2. Check switch FDB moves, egress discards and link/FCS counters. Risk is low with existing observation points. Keep the live router read-only.
3. If the loss is localized to elitedesk, repeat with one combined queue and verify ATR matches still increment before interpreting the result. Loss disappearing with active ATR favors a multiqueue interaction. Then restore the queue count and vary coalescing and ring depth individually for H5. Check kernel logs for AER, DPC, ixgbe resets and link events, then test a known-good DAC and an alternate supported kernel separately. Queue-specific stalls favor H1/H5, PCIe errors coinciding with loss favor H4, and errors following the DAC favor the physical path. Risk is standby link interruption and reduced throughput during the single-queue test. — [satisfied]

**Q3 Fix.** If the crossover reproduces the effect, expose an opt-in per-interface `ntuple` setting in nix-router-optimized, defaulting to existing behavior, and enable it on elitedesk’s X520 LAN port. Apply `ethtool -K … ntuple on` through the existing systemd NIC tuning path once the device is present and channel/ring settings are applied. Verify readback, and ensure device re-add reruns the tuning after driver rebind. Add docs and an eval check for the generated configuration. On this ixgbe path, `ntuple on` selects perfect-filter mode and disables ATR signature learning. Ordinary RSS still distributes unclassified traffic. Check for explicit n-tuple rules and measure queue/CPU balance, throughput and latency under forwarding load. The cost is losing ATR’s adaptive RX/TX locality and potentially resetting the interface when applying the setting. A module parameter would require verifying support in the exact driver build and checking its scope. Keep the workaround per interface until broader evidence warrants changing router defaults. If the crossover fails, follow the capture boundary and correct the link, bridge, driver or queue fault it identifies. — [satisfied-conditional: persist the setting if reproducible or retain it as a measured mitigation pending diagnosis]

**Q4 Hardware decision.** Qualify the available ConnectX-4 before failover. Replace the X520 for production if PCIe disappearance recurs, the fault follows the card in a controlled swap, or the standby cannot pass sustained TCP DNS, zone-transfer and forwarding tests with the mitigation. The previous dropout survived rebind and FLR, making recovery time relevant even if ATR mitigation holds. If both cards show PCIe faults in that slot, investigate the host slot, power and PCIe path. For ConnectX-4, use `mlx5_core` for Ethernet and verify the exact SKU, firmware, Ethernet port mode where configurable, and supported SFP+/DAC, link rate and switch pairing. Start with default RSS and flow steering, inspect effective settings and installed rules, and verify queue distribution under load. Test cold boot, reboot and link recovery, and account for changed interface names and MACs in NixOS and failover configuration. — [satisfied-conditional: qualify the replacement on the intended slot, cable and switch port]

#### Position B: Gemini (`agy -p`)

**Q1 Root cause.** 
1. **H1 (Rank 1 — 82599 Flow Director ATR Hardware Filter Drop/Mis-steer):** Overwhelmingly supported by E11 and E13. In the Intel 82599ES `ixgbe` driver, Application Targeted Routing (ATR) inspects outgoing TCP SYNs in `ixgbe_atr()` and transmits context descriptors to program reverse signature filters (15-bit bucket hash, 16-bit signature) directly into the hardware Flow Director (FDIR) table. When a signature collision occurs, or when an insertion collides with hardware lookup/state transitions, the 82599 ASIC drops the matching RX frames at the MAC/filter level before host DMA. This explains every observed anomaly:
   - **Per-instance sticking (E7, E8):** The outgoing SYN writes the signature filter. As long as that filter entry remains in the FDIR table, *all* incoming SYN-ACK retransmits for that exact connection match the corrupt/black-holed entry and are silently dropped. When tested 65 s later (E8), the ephemeral filter had aged out or overwritten cleanly.
   - **Invisible to tcpdump (E7, E10):** Packet capture occurs after DMA into the host ring buffer; ASIC FDIR drops occur before DMA. `rx_missed_errors` and `rx_no_dma_resources` remain 0 because the drop is an internal filter action, not a ring FIFO overflow.
   - **TCP-only, UDP unaffected (E2):** In `ixgbe`, ATR only tracks TCP flows (`IPPROTO_TCP`); UDP DNS queries never generate ATR signature rules.
   - **Zero failures under `ntuple on` (E11, E13):** In `ixgbe`, enabling `ntuple` explicitly disables automatic ATR descriptor programming (`IXGBE_FLAG_FDIR_HASH_FLAG`). With ATR off, `fdir_match` froze at 16,875 and 6,920 queries achieved a 0.00% failure rate (expected ~250 failures at baseline).
2. **H4 (Rank 2 — Hardware/Firmware Instability from PCIe Dropout):** Bead `nch-sny.31` recorded `ixgbe 0000:01:00.1` logging "Adapter removed" with FWSM `0xFFFFFFFF` requiring a warm reboot. Degraded ASIC state or marginal firmware (`0x000161ab 1.3082.0`) could exacerbate FDIR table corruption during register/descriptor writes.
3. **H5 (Rank 3 — Interaction with `router-optimizations`):** Setting `rx-usecs 1` and 4096 descriptors stresses driver/ASIC descriptor processing and increases race windows between TX ATR filter programming and RX arrival.
4. **H2 (Rank 4 — L2 / ARP / MAC Flapping):** Weakened by E6 (static ARP), E7 (router egress verified), and E8 (reused ports succeed).
5. **H0 and H3 (Disproven):** Eliminated by E5 (`lport=8888`, not `:53`) and E10 (no XDP/tc). — [satisfied-conditional: E14 control soak confirms failure return under ATR-on]

---

**Q2 Discriminating experiments.**
1. **Complete E14 Control Soak (`dns-soak-atr-on`):**
   - *Action:* Allow the running 2 h soak with `ntuple off` (ATR on) to finish.
   - *Expected:* Return of ~1–5% TCP timeouts (~70–300 drops) and resumed incrementing of `fdir_match`. If failures do not return, H1 is weakened in favor of transient state/H4.
   - *Risk:* None (read-only DNS probes to standby).
2. **BPF Trace of ATR Allocation for Dropped Flows:**
   - *Action:* Run `bpftrace -e 'kprobe:ixgbe_atr { printf("ATR flow: sport=%d dport=%d\n", arg1, arg2); }'` while running TCP SOA queries, correlating failing source ports with the specific RX queue index assigned by `ixgbe_fdir_add_signature_filter_82599`.
   - *Expected:* Correlates the dropped SYN-ACKs directly to the specific ATR rule programming event.
   - *Risk:* Negligible (safe kernel probe on standby).
3. **Decouple `router-optimizations` Coalescing from ATR (Test H5 vs H1):**
   - *Action:* Revert `rx-usecs 1` to standard adaptive moderation (`ethtool -C enp1s0f1 adaptive-rx on rx-usecs 3`) while keeping ATR enabled (`ntuple off`), running a 30-min soak.
   - *Expected:* If failures persist, H1 is an independent 82599 silicon flaw; if they disappear, H5 tuning is the primary co-factor.
   - *Risk:* Low.
4. **PCIe Bus and Link Health Audit (Test H4):**
   - *Action:* Check `lspci -vvv -s 0000:01:00.1` for PCIe Advanced Error Reporting (AER) correctable/uncorrectable errors and monitor `dmesg -T` for ixgbe link flapping or register read timeouts.
   - *Expected:* Distinguishes whether the card is physically dying or just exhibiting known 82599 ATR errata.
   - *Risk:* None. — [satisfied]

---

**Q3 Fix.**
- **Persistent Fix in `nix-router-optimized`:**
  Permanently disable ATR on `enp1s0f1` by enabling `ntuple` filtering via systemd network configuration or link post-up:
  ```nix
  networking.interfaces.enp1s0f1.postUp = "${pkgs.ethtool}/bin/ethtool -K enp1s0f1 ntuple on";
  ```
  *(Or configure `ReceiveNTupleFilter=yes` in the systemd-networkd `[Link]` unit).*
- **Policy for Router Roles:**
  Disable ATR globally for router/firewall roles. ATR is designed for end-host socket affinity (directing reverse packets to the core running the socket). For a router forwarding transit traffic, ATR provides zero benefit, consumes TX cycles, and introduces 82599 signature table collision drops.
- **Costs:**
  Negligible. Incoming TCP traffic will fall back to standard 4-tuple Receive Side Scaling (RSS) distributed across the 8 RX queues. On modern x86 with shared L3 cache, inter-core cross-invalidation is unmeasurable for DNS and routing workloads, and disabling ATR saves TX descriptor cycles.
- **Alternative (if not ATR):**
  Split the shared L2 topology by moving management (`eno1`) and LAN (`enp1s0f1`) to dedicated VLANs to eliminate ARP/MAC ambiguity, and restore standard interrupt coalescing (`rx-usecs` 3–50). — [satisfied]

---

**Q4 Hardware decision.**
- **Replacement Criteria:**
  Replace the X520 with the ConnectX-4 if:
  1. Any further PCIe dropout, FLR failure, or FWSM register read errors (`0xFFFFFFFF`) occur.
  2. E14 shows non-deterministic behavior that `ntuple on` does not reliably eliminate.
  *Note:* Because elitedesk is slated to become the **primary router**, retaining an NIC with a documented `nch-sny.31` "Adapter removed" bus crash on its resume path is an unacceptable production risk.
- **ConnectX-4 Considerations:**
  - **Driver:** Uses in-tree `mlx5_core`. Fully supported in NixOS kernels (`hardware.enableRedistributableFirmware = true;`).
  - **Steering:** ConnectX-4 utilizes hardware RSS and standard flow steering engines; it has no problematic ATR signature-hash collision behavior.
  - **Transceiver/DAC Compatibility:** Mellanox firmware does not enforce vendor lockouts, completely eliminating the brittle `allow_unsupported_sfp=1` module parameter. Set fixed speed (`ethtool -s enp... speed 10000 autoneg off`) if DAC auto-negotiation hesitates. — [satisfied]

#### Position C: Claude (`claude -p`)

**Q1 Root cause.**

1. **H1, refined: ATR or Flow Director state on the 82599 causes the frames to be dropped, not just sent to the wrong queue.** E13 is the strongest evidence. It ran 0/6920 failures with `fdir_match` frozen, where E2's rate predicts about 250. That is hard to explain by chance.

   There is a gap, though. Plain ATR mis-steering, such as an 82599 signature-filter collision (bucket hash plus a 16-bit signature, never aged), only moves a flow to a different RX queue. The frame would still become an skb, and `tcpdump -i any` would still see it (E7). So the mechanism needs a silent hardware discard after the Flow Director match. Candidates I can't tell apart from this evidence:
   - (a) the filter points at a queue index that is invalid or not being serviced;
   - (b) a race or failed `FDIRCMD` when installing the filter leaves a corrupt bucket entry;
   - (c) a drop on a per-queue counter (QPRDC) that ixgbe doesn't export.

   Two observations fit this picture:
   - **Per connection instance (E8):** ATR installs a filter when it sends the SYN, from the CPU and TX queue that sent it.
   - **Burstiness, and the clean short run in E12:** stale entries build up because `fdir_overflow` stays at 0, so the table is never re-initialised. Toggling ntuple flushes it.
2. **H4: a fault on this card, its firmware or the driver.** This could be the same root as the PCIe dropout, with Flow Director logic or packet-buffer corruption on a marginal card. It isn't independent of H1: it may be *why* ATR misbehaves here when it is fine on most 82599s.
3. **H5: our tuning** (8 queues, 4096-entry rings, `rx-usecs` 1). This would only matter by making the queue-index or timing condition in (a)/(b) more likely. Low.
4. **H2: L2 or the switch.** Low. ARP is clean (E6). No L2 mechanism would select by connection instance and also stop when ATR is turned off.
5. **New, H6: the DAC or SFP under `allow_unsupported_sfp`.** Very low. Physical-layer loss would hit UDP and show up in `rx_crc_errors`, which is 0.

**Marker:** [satisfied-conditional: E14 reproduces failures while `fdir_match` grows]

**Q2 Discriminating experiments.**

1. **Read E14** (no risk).
   - If failures return and `fdir_match` grows: H1 or H4. Go to step 2.
   - If 0 failures: H1 is weakened, because the toggle only flushed the table. Rerun after a cold boot with no toggling.
2. **Count hardware RX against the capture during a failure** (ATR on, low risk). Snapshot the full `ethtool -S` (`rx_pkts_nic`, `fdir_*`, every `rx_queue_N_packets`) and `ethtool -d enp1s0f1` (FDIR and QPRDC registers) every second. Run `tcpdump` with a filter on the probe's ports.
   - If the NIC hardware counter rises by the number of missing SYN-ACKs but no skb appears: the drop is inside the NIC or driver (H1/H4).
   - If the counter stays flat: the frames never arrived (H2). Confirm with a switch port mirror, or by capturing on router's Proxmox bridge or tap.
3. **Find the steered queue.** Use bpftrace on `ixgbe_atr` (or `ixgbe_fdir_add_signature_filter_82599`) to log the queue index and hash for each SYN. Correlate those with the failed connections.
   - If failed flows map to one queue or an odd index: (a).
   - If hashes collide with earlier flows: collision, which also needs a drop.
4. **Same card, other port** (`enp1s0f0`, ATR on, same DAC). Then swap the DAC.
   - If failures follow the port or cable: H4/H6.
   - If failures follow ATR on any port: H1.
5. **Revert H5.** Set the default queue count, rings and coalescing, and keep ATR on.
   - If failures disappear: H5 is involved.
6. **Optional: change the driver version.** Try LTS kernel 6.12, or Intel's out-of-tree ixgbe, with ATR on.

All of this is on elitedesk, plus read-only capture on router.

**Marker:** [satisfied]

**Q3 Fix.** Disable ATR per interface, opt-in. Don't make it a global change to router defaults, because option names and defaults are a public interface.

- **Option:** something like `router.optimizations.nics.<name>.flowDirectorATR = false`, which applies `ethtool -K <if> ntuple on`.
- **How to apply it:** a oneshot unit `BindsTo`/`After` the device unit (`sys-subsystem-net-devices-<if>.device`), re-run on link or driver reset. I believe recent systemd has `NTupleFilter=` in `.link` files, which would be cleaner and survive driver rebinds, but check that against the systemd version in NixOS 26.05.
- **Eval check:** assert that the unit or `.link` setting exists, and that its `ExecStart` passes `bash -n`.
- **Doc:** a `# WHY:` tag pointing at this incident.

Costs:
- RX loses CPU affinity to the TX CPU, so RSS alone spreads the load. That is negligible at homelab rates.
- ntuple on switches Flow Director into perfect-filter mode. The packet-buffer reservation is similar.
- The setting has to be re-applied after every reset. Any re-init that drops it brings the bug back silently, so the health check should alert on `ntuple-filters: off`.
- An alternative is a single queue, which also disables ATR, but it costs throughput. I'd only use it as a diagnostic.

If it isn't ATR:
- H4: replace the card (Q4).
- H5: revert the specific tuning knob.
- H2: fix the switch or L2 design, which means splitting management and LAN into separate VLANs.

**Marker:** [satisfied-conditional: E14 or step 2 attributes the drops to Flow Director]

**Q4 Hardware decision.** Replace the X520 before elitedesk becomes primary if any of these happen:
- failures continue with ATR off over a longer soak (24 h or more);
- step 2 or step 4 points at the card or port rather than ATR;
- any repeat of the "Adapter removed", AER or FWSM 0xFFFFFFFF events.

Even if ATR-off fixes the TCP loss, it does nothing for the PCIe dropout (`nch-sny.31`). That risk is independent, and it is severe for a primary router: a warm reboot was the only recovery. The card is also end-of-life and needs `allow_unsupported_sfp`. My lean is to swap it pre-emptively when promoting elitedesk, and to keep the X520 only for testing.

ConnectX-4 or ConnectX-4 Lx checklist:
- **Driver:** `mlx5_core` is in-tree. Update the firmware with `mstflint` or `mlxfwmanager`. Check that PSID is a stock Mellanox ID, not OEM-locked.
- **Link type:** on VPI cards, set `LINK_TYPE_P1=2` (Ethernet) with `mlxconfig`.
- **PCIe:** use a slot with x8 lanes (x4 is fine for 10G). Check `lspci -vv` for the link width and that AER is clean.
- **SFP:** there is no vendor lock, so the DAC should work at 10G. On 25G models, confirm the link negotiates 10G.
- **Flow steering:** there is no ATR equivalent. Defaults are RSS, with aRFS only if you enable ntuple and RFS. Leave both off.
- **Config impact:**
  - the MAC changes, so pin the name with a `.link` file and update any MAC-keyed config or reservations;
  - re-check the `router-optimizations` ring and coalescing values against mlx5 limits;
  - rerun the E2 and E13 soak as an acceptance test before failover.

**Marker:** [satisfied-conditional: operator accepts pre-emptive swap given `nch-sny.31`; otherwise needs the 24 h ATR-off soak plus a clean AER log]

#### Position D: GitHub Copilot (`copilot -p`)

**Q1 Root cause.** Rank: H1 (Flow Director ATR misdirection) > H4 (PCIe/driver flakiness) > H2 (L2) > H5 (ring/coalescing tuning) > H3 (disproven, E10). E13 is the strongest single data point: 2h with ATR disabled, 6920/6920 TCP succeeded, `fdir_match` frozen — against an expected ~250 failures at E2's rate, that's a near-impossible null result under any hypothesis except one tied to ATR's RX steering. Mechanism: 82599 ATR builds a perfect-match filter from the first SYN-ACK's 4-tuple hash and steers subsequent packets of that flow to a specific queue; a signature-hash collision with another concurrently-tracked flow (or a stale/incorrectly-programmed filter entry) can silently misroute or drop RX descriptors for that queue's flow context without incrementing `rx_missed_errors` (those count only global ring-exhaustion drops, not per-filter misrouting). This explains: per-connection (not per-4-tuple) stickiness (E8) — ATR filters are rebuilt per new TCP handshake, so retries on the same ports but a new connection instance get a fresh ATR decision; UDP immunity (E2) — ATR only engages for TCP; and why ECN state doesn't matter (E9) — it's a hash-table/queue-index issue, not a flag issue. H4 can't be fully excluded — the earlier "Adapter removed" FWSM 0xFFFFFFFF event (nch-sny.31) shows this specific card/slot has a marginal PCIe link, and marginal links can manifest as intermittent RX queue stalls that look similar to ATR misdirection — but H4 doesn't explain why E13's 2h soak was perfectly clean while earlier sessions weren't, unless the PCIe event was a one-off already recovered by the warm reboot. [satisfied-conditional: E14 comes back positive for failures with ATR re-enabled]

**Q2 Discriminating experiments.** 1) Finish E14 (ATR-on soak, already running, read-only on elitedesk only) — if failures return at a similar rate to E2, H1 is confirmed and H4/H5 are demoted; if clean, H1 is falsified and we pivot hard to H4/H2. Low risk. 2) During the next ATR-on failure, capture `ethtool -S enp1s0f1 | grep fdir` immediately before/after and `ethtool -x enp1s0f1` (RSS/indirection) rather than toggling `ntuple` — toggling flushes the filter table and so far has been inconclusive (E12); a non-destructive read during an active failure window is needed. 3) Use `ethtool -u enp1s0f1` or `ip link ... ntuple-flow-all` (if supported) to dump active Flow Director filter rules at fail time to look for hash collisions directly. 4) If hardware suspicion remains, check PCIe AER counters (`dmesg`/`lspci -vvv` on elitedesk, read-only) and link speed/width (`lspci -s <addr> -vv | grep LnkSta`) to rule out link renegotiation coincident with failures — correlate timestamps against the TCP failure log. 5) Only as a last, elitedesk-only, reversible step: swap elitedesk's NIC port (if dual-port) or move to a different PCIe slot to see if failures move with the card or the slot (discriminates H4/H1 vs H2). Router stays read-only throughout. [satisfied]

**Q3 Fix.** If H1 confirmed: persist `ntuple on` (ATR off) for `enp1s0f1` via NixOS `networking.interfaces` post-up / systemd-udev `ExecCmd` or an `ethtool` services.udev rule scoped to this NIC, ideally as a reusable router-optimizations option (e.g., `router.net.disableFlowDirectorATR` applied to any ixgbe interface acting in a router/standby-router role) rather than a one-off hack — document the WHY tag pointing at this incident. Cost: ATR gives per-flow RX queue affinity for cache locality; disabling it falls back to Toeplitz RSS hashing, which is still multi-queue but loses some flow-to-core pinning — on a DNS/router workload at these packet rates this is very likely immaterial (not a high-PPS flow problem) so the cost is near zero. Alternative: keep ATR on but increase `rx-flow-hash` symmetry or pin via explicit `ethtool -N ntuple-rules` per flow — more fragile, don't recommend. If not ATR (H4 confirmed by PCIe evidence): fix is hardware, not config — see Q4. [satisfied-conditional: E14 confirms ATR as the mechanism]

**Q4 Hardware decision.** Replace the X520 if: (a) E14 reproduces failures with ATR on AND a later PCIe AER/link-width anomaly also correlates with failure timestamps (suggesting the ATR workaround is masking, not fixing, a degrading card), or (b) the "Adapter removed" event recurs even once more under any configuration — a card that drops off PCIe is a standby-router disqualifier regardless of the TCP bug, since failover reliability is the whole point. If ATR-off is clean indefinitely and no further PCIe events occur, the X520 is fine to keep with the config fix — don't swap for its own sake. ConnectX-4 considerations: it uses `mlx5_core`, a different, generally more actively maintained driver with different RX steering (flow steering via hardware flow tables, not Flow Director's hash-based ATR) — much less likely to exhibit this exact ATR collision class of bug, but verify: (1) firmware/driver support matrix for the specific ConnectX-4 variant against the installed kernel 6.x, (2) SFP/DAC compatibility — ConnectX-4 is typically stricter about unsupported-module enforcement than X520's `allow_unsupported_sfp=1` escape hatch, so the existing DAC/SFP may need to be on Mellanox's compatibility list or require `mlx5_core.probe_vf`/MCRA unlocking, (3) default flow-steering mode (aRFS/RSS) and queue count parity with current `rx-usecs`/ring tuning so router-optimizations doesn't need a parallel ixgbe/mlx5 branch indefinitely. [needs more evidence: E14 result and a PCIe AER check on elitedesk]

#### Position E: DeepSeek (API)

**Q1 Root cause.** Ranked: **H1 (ATR/Flow Director RX mis-steering) — most likely**, then **H4 (ixgbe/firmware/PCIe instability)**, then **H5 (tuning)**, then **H2 (L2)**. Mechanism: on 82599, ATR programs a Flow Director filter keyed on a hash of the TCP 4-tuple to steer RX to a specific queue. If the signature hash collides with or overwrites an entry for a flow whose SYN-ACK arrives on a different hash (e.g., the reply direction hashes differently, or the filter is stale/pointing at a queue that isn't draining), the frame can be dropped in hardware before the stack — consistent with E7 (router egresses SYN-ACKs, elitedesk captures none on any iface) and E10 (no XDP/tc). E11/E13 are strong: ATR off → 0/6920 failures and `fdir_match` frozen; E2's ~3.6% rate would have produced ~250 failures. E8 (loss tied to connection instance, not 4-tuple) fits ATR because the filter is programmed per-connection at SYN and can be stale/colliding for that instance; reusing the port later gets a fresh filter. E9 rules out ECN. H4 remains plausible because `nch-sny.31` shows the card can fall off PCIe with FWSM 0xFFFFFFFF — a marginal DAC/SFP under `allow_unsupported_sfp=1` or a flaky slot could cause intermittent RX loss, but that would not be so cleanly toggled by `ntuple`. H5 is weak: `rx-usecs 1` and GRO don't drop SYN-ACKs pre-capture. H2 is weakened by E6 and by UDP being clean. I am not certain of the exact 82599 ATR collision path; E14 is the decisive control.

**Q2 Discriminating experiments.** Ordered, low risk (router read-only):
1. **Finish E14** (2 h ATR-on soak). Expected: failures return at ~1–4% under H1; clean under H4/H5. Risk: none (standby traffic only).
2. **`ethtool -S enp1s0f1` delta during E14 failures**: expect `fdir_match`/`fdir_miss` moving and `rx_missed_errors`/`rx_no_dma_resources` staying 0 under H1; under H4 expect `rx_*` errors or link/PCIe events (`dmesg`, `lspci -vv` AER). Risk: none.
3. **`ethtool -n enp1s0f1` / `-u` dump of Flow Director filters** during a failing connection: under H1 expect a filter for the flow pointing at a queue; absence or wrong queue supports collision/eviction. Risk: none.
4. **Pin a single RX queue** (`ethtool -L enp1s0f1 combined 1`) with ATR on: if failures vanish, queue-steering is implicated (H1); if they persist, H4/H5. Risk: brief link reconfig on standby.
5. **Swap DAC/SFP and slot** on elitedesk, re-run ATR-on soak: isolates H4/`allow_unsupported_sfp`. Risk: physical, standby only.
6. **Router-side mirror/tcpdump on `enp6s16`** already done (E7); add switch port mirror if available to confirm frames leave the wire. Risk: read-only.

**Q3 Fix.** If E14 confirms ATR: persistent fix in `nix-router-optimized` is to disable ATR for router roles — set `ntuple on` via a systemd/udev `ethtool` unit (or NetworkManager/`systemd-networkd` `.link`/`Ethtool` settings) applied at boot and after rebind, since `ntuple` is not a module param. Cost: lose ATR RSS steering benefit (minor CPU/queue imbalance on 8 queues); `fdir_match` stays flat, so no hardware flow steering — acceptable for a DNS/router role. Alternative: `ixgbe` module option to disable ATR if one exists in this kernel (verify; historically ATR is toggled via ethtool, not module param). Do **not** rely on a one-shot toggle (E12 showed it may just flush a stale table). If not ATR: pursue H4 — replace DAC/SFP, drop `allow_unsupported_sfp`, check slot/AER, and consider RMA given `nch-sny.31`.

**Q4 Hardware decision.** Replace the X520 when: (a) E14 confirms ATR and disabling it is unacceptable operationally, or (b) H4 evidence appears — repeat PCIe drop, AER errors, FWSM 0xFFFFFFFF, or RX errors that persist with ATR off and a known-good DAC/SFP. The single `nch-sny.31` event plus a clean ATR-off soak argues for keeping the card only if ATR-off is stable; a second dropout justifies replacement. ConnectX-4 needs: `mlx5_core` (in-tree, fine on 6.18), firmware via `mlx-firmware`, flow steering defaults (steer_mode/`ethtool -N`/`tc` — verify ATR-equivalent behavior is off by default), and SFP/DAC compatibility (Mellanox is stricter than `allow_unsupported_sfp`; use a coded DAC or supported module). Budget a re-validation soak before failover. [satisfied-conditional: E14 result]


*IC synthesis pending E14 (ATR-on control soak, ends about 11:50).*
