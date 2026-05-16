# Router Discussions

This directory contains deliberative transcripts on complex architectural or protocol-related problems.

| ID | Title | Date | Status |
|----|-------|------|--------|
| [01](./01-ipv6-vpn-redirection.md) | IPv6 VPN Redirection & Dynamic Prefix Handling | 2026-05-02 | Closed |
| [02](./02-ipv6-redirection-standards-vs-pragmatism.md) | Standards vs. Pragmatism in IPv6 Redirection | 2026-05-02 | Closed |
| [03](./03-router-backup-standby-and-shared-wan.md) | Router-Backup Standby and Shared-WAN Failure Mode | 2026-05-09 | Closed |
| [04](./04-router-security-zones-recovery-review.md) | Recovered Security/Zones Work Review | 2026-05-09 | Closed |
| [05](./05-router-bgp-support-boundary.md) | Whether BGP Should Be a Supported Flake Option | 2026-05-16 | Closed |

## Methodology

These discussions are conducted using a multi-agent deliberation protocol:
1.  **DeepSeek**: Focuses on protocol-level traps and network engineering realities.
2.  **Gemini**: Focuses on user-centric use cases (e.g., travel routers) and high-level UX.
3.  **GitHub Copilot**: Focuses on developer experience and integration patterns.
4.  **Codex**: Focuses on the low-level implementation details (nftables, systemd-networkd, kernel hooks).

Results from these discussions are used to generate declarative work items in `docs/work-items/`.
