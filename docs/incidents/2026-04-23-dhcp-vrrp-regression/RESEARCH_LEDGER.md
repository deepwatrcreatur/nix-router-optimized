# DHCP / VRRP Regression: Research Ledger

## Shared Facts
- Existing clients renew via unicast.
- `DHCPDISCOVER` broadcasts are visible in `tcpdump` on `enp6s16`.
- Kea 3.0.2 in the "Third-State" (`raw` + bare interface + `use-routing`) correctly polls the raw socket (E34).
- Kea HA in `READY`/`WAITING` states can suppress local DHCP service even when packet receive is healthy (E35, E36).
- The `server-id` crash was a generation-specific artifact, not a current-source invariant (E37).

## Hypotheses

| ID | Hypothesis | Confidence | Status |
| --- | --- | --- | --- |
| **H6** | **Kea 3.x fails to poll its raw socket in some configurations.** | **Resolved** | The "Third-State" (bare interface + `use-routing`) induces correct polling behavior. |
| **H7** | **HA State Silence is masking broadcast receive success.** | **Confirmed** | Verified by forcing `PARTNER-DOWN` transition (Position AK), which immediately restored client servicing. |
| **H8** | **The remaining HA outage is caused by deployment mismatch between nodes, not another Kea code-path bug.** | **Active** | Live configs and logs now point at mixed HA transports across `router` and `router-backup`; this still needs matching deployment validation. |
| D3 | Broadcast invisibility is a pure UDP socket limitation. | Disproven | Verified that `PF_PACKET` sockets *can* see broadcasts (E15), and Kea now uses it correctly. |

## Experiment Ledger (Key Probes)

| ID | Probe | Result | Interpretation |
| --- | --- | --- | --- |
| E34 | strace Managed Third-State | **SUCCESS.** Kea is calling `recvmsg()` on FD 23 (Raw). | **H6 Fixed.** Third-state induces correct polling. |
| E35 | HA Control State Inspection | `router` stuck in `READY`. | **Mask identified.** `READY` state drops packets. |
| E36 | Force `PARTNER-DOWN` via timeout | **SUCCESS.** New clients instantly served. | **Regression Cleared.** The problem was HA convergence. |
| E37 | HA URL Forensic Audit | Found localhost regression in `65a57b4`. | Found source of one-way HA control plane. |
| E38 | Lease command hook audit | `lease4-get-page` missing until `libdhcp_lease_cmds.so` was loaded. | HA sync depends on the lease command hook, not just `libdhcp_ha.so`. |
| E39 | LAN-plane retest after lease hook | Backup now fails to reach `10.10.10.2:8000` with `No route to host`. | Software blockers cleared; remaining issue is disconnected service-plane topology. |
| E40 | Backup Kea carrier guard | Staged backup-only `ExecCondition` + carrier sync path/service. | Management-only standby no longer pretends to participate in LAN-plane HA. |
| E41 | Local worktree build validation | **SUCCESS.** `nixosConfigurations.router` and `router-backup` build successfully in `unified-nix-configuration-router-pr` when overridden to the local `nix-router-optimized` worktree containing `localAddress`, `libdhcp_lease_cmds.so`, LAN-plane peer wiring, and the backup carrier guard. | The remaining work is persistence/release hygiene and physical HA retest, not Nix evaluation failure. |
| E42 | Post-PCI-move link audit on `router-backup` | Interface naming remained stable; `enp3s0` (LAN) regained carrier and `10.10.10.3/16`, while `ens17` (WAN) still had `NO-CARRIER`. | The card move did not create an in-guest naming bug. Current boundary is live wiring/deployment state, not interface discovery. |
| E43 | Live HA transport comparison after LAN cable reconnect | `router` was targeting `http://10.10.10.3:8000/`, while `router-backup` was still configured for `http://192.168.100.99:8000/` / `http://192.168.100.100:8000/`; logs on both sides showed corresponding timeout/refusal behavior. | The latest observed state is a mixed deployment, so the incident is not yet proven resolved. |
