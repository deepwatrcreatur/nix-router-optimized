# Router Discussions

This directory contains deliberative transcripts on complex architectural or protocol-related problems.

| ID | Title | Date | Status |
|----|-------|------|--------|
| [01](./01-ipv6-vpn-redirection.md) | IPv6 VPN Redirection & Dynamic Prefix Handling | 2026-05-02 | Closed |
| [02](./02-ipv6-redirection-standards-vs-pragmatism.md) | Standards vs. Pragmatism in IPv6 Redirection | 2026-05-02 | Closed |
| [03](./03-router-backup-standby-and-shared-wan.md) | Router-Backup Standby and Shared-WAN Failure Mode | 2026-05-09 | Closed |
| [04](./04-router-security-zones-recovery-review.md) | Recovered Security/Zones Work Review | 2026-05-09 | Closed |
| [05](./05-router-bgp-support-boundary.md) | Whether BGP Should Be a Supported Flake Option | 2026-05-16 | Closed |
| [06](./06-recent-work-code-review-and-refactor-boundary.md) | Recent Work Code Review and Refactor Boundary | 2026-05-17 | Closed |
| [07](./07-styx46-incorporation-boundary.md) | Whether `styx46` Should Enter the Flake Boundary | 2026-05-18 | Closed |
| [08](./08-styx46-incorporation-strategy-and-project-identity.md) | Best Incorporation Strategy for `styx46`-Style Functionality | 2026-05-18 | Closed |
| [09](./09-declarative-clat-design-review-and-first-slice-boundary.md) | Declarative CLAT Design Review and First-Slice Boundary | 2026-05-18 | Closed |
| [10](./10-clat-first-slice-lessons-cleanup-and-refinement.md) | CLAT First-Slice Lessons, Cleanup, and Refinement | 2026-05-20 | Closed |

## Methodology

These discussions are conducted using a multi-agent deliberation protocol:
1.  **DeepSeek**: Focuses on protocol-level traps and network engineering realities.
2.  **Gemini**: Focuses on user-centric use cases (e.g., travel routers) and high-level UX.
3.  **GitHub Copilot**: Focuses on developer experience and integration patterns.
4.  **Codex**: Focuses on the low-level implementation details (nftables, systemd-networkd, kernel hooks).

Results from these discussions are used to generate declarative work items in `docs/work-items/`.
