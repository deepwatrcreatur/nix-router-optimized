# AI-Driven Incident Response Template

This template is derived from the **2026-04-23 DHCP/VRRP Regression** incident. It is designed to coordinate multiple AI agents and human engineers during complex, multi-layered system failures.

## 1. SUMMARY.md (The Source of Truth)
- **Status:** [ACTIVE | DEGRADED | RESOLVED]
- **Incident Summary:** High-level overview for fast onboarding.
- **Verified Facts:** Bulleted list of settled technical truths (evidence-backed).
- **Navigation:** Links to the Ledger and Active Discussion.

## 2. RESEARCH_LEDGER.md (The Data Room)
- **Shared Facts:** Baseline observations (e.g., "Packet capture shows X").
- **Hypotheses Table:** 
  | ID | Hypothesis | Confidence | Status |
  | --- | --- | --- | --- |
  | H1 | [Description] | [Low/High] | [Open/Confirmed/Disproven] |
- **Experiment Ledger (E1-EX):**
  | ID | Probe | Result | Interpretation |
  | --- | --- | --- | --- |
  | E1 | [The Command/Action] | [Output/Observation] | [Technical takeaway] |

## 3. ACTIVE_DISCUSSION.md (The Blackboard)
- **Signed Positions:** Use "Position [A-Z]" for agent synthesis.
- **Rules of Engagement:**
  - One agent per Position.
  - Respect previous positions but feel free to refute with evidence from the Ledger.
  - Keep summaries concise; point to the Ledger for raw data.

## 4. Operational Hygiene
- **Forensic First:** Use `strace`, `tcpdump`, and `nix eval` before changing configuration.
- **The "Mask" Rule:** Always check if a "fixed" symptom is actually being masked by an upper-layer logic (e.g., HA states, firewall drops).
- **Generation Mapping:** Always map live failure symptoms to specific NixOS generations or Git commit hashes.
