## Discussion 01: IPv6 VPN Redirection & Dynamic Prefix Handling

**Topic:** Implementing robust IPv6 traffic redirection via VPN for travel routers and site-to-site scenarios with dynamic prefixes.
**Context:** [Reddit Discussion](https://www.reddit.com/r/ipv6/comments/1szv7os/redirecting_traffic_via_a_vpn/)

### DeepSeek

**The Problem — The "Ingress Filtering" Trap:** The Reddit post highlights a critical IPv6 reality: without NAT, you can't just route packets out a VPN tunnel and expect them to work if the source address doesn't belong to the remote site's prefix. The remote ISP will drop them (BCP38), and return traffic won't know where to go.

**Proposed Feature — Prefix-Aware Policy Routing (PBR):** The `router-networking` module should support **Source-Specific Routing (SADR)**. If a packet comes from a specific local prefix (or ULA range), it should be forced into the VPN table.
- **Dynamic Update Hook:** We need a way for `router-networking` to react to prefix changes. If the VPN client receives a new prefix delegation (PD) from the server, we need to update the local routing tables automatically.
- **NPTv6 (Network Prefix Translation):** For travel routers where "true" IPv6 is too hard due to ISP restrictions, we should provide an `NPTv6` module. This is cleaner than NAT66 and allows mapping the local (dynamic) prefix to a remote (dynamic) prefix 1:1. `[inferred]`

[satisfied]

### Gemini

**The Travel Router Use Case:** A travel router (e.g., GL.iNet running NixOS) often sits behind a hotel WAN that might only provide a single `/64` or even just a single IPv6 address.
- **NAT66 as a "Last Resort" Toggle:** While we prefer NPTv6, we should acknowledge that some users just want "it to work" for geo-unblocking. We should add a `services.router-firewall.ipv6Masquerade` option for specific interfaces (like VPNs).
- **ULA Integration:** We should make it easier to assign a stable ULA prefix to the LAN. If we have stable ULAs, we can use NPTv6 to map those ULAs to whatever dynamic GUA (Global Unicast Address) the VPN tunnel is currently providing. This decouples local client addressing from the "churn" of the VPN prefix. `[observed]`

[satisfied]

### GitHub Copilot

**User Experience (UX) for Redirection:** Most users don't want to redirect *all* IPv6. They want to redirect their Apple TV or a specific VLAN.
- **VLAN-Based VPN Exit:** We should allow assigning a VPN exit node to a specific `routedInterface`. 
  ```nix
  services.router-networking.routedInterfaces.streaming = {
    vpnExit = "tailscale0"; # Automatically handles the routing/masking
  };
  ```
- **DNS64/NAT64 Interaction:** If we are redirecting via a VPN that doesn't support IPv6 (or has poor IPv6), the router should be able to perform NAT64 *at the tunnel entry*, forcing the client to use IPv4 over the VPN while thinking it's using IPv6.

[satisfied]

### Codex

**Implementation Details — nftables & systemd-networkd:**
- **nftables Marks:** We can use `router-firewall` to mark packets from specific source MACs or IP ranges.
- **IP Rule:** `ip -6 rule add fwmark 0x1 table vpn_route`.
- **NPTv6 Module:** NixOS already has `networking.nftables.tables`, but it lacks a high-level NPTv6 abstraction. We should build `services.router-nptv6` which takes `internalPrefix` and `externalInterface` and handles the mapping.
- **The "Dynamic" Problem:** We need a small daemon or a `networkd` hook that monitors the GUA of the VPN interface and updates the NPTv6 `externalPrefix` accordingly. This is the "missing link" for travel routers. `[observed]`

[satisfied]

### Synthesis — Q01

**Proposed Strategy:**
1.  **Introduce NPTv6 Module:** Create `services.router-nptv6` to allow 1:1 prefix translation between a stable local prefix (GUA or ULA) and a dynamic VPN prefix.
2.  **Enable IPv6 Masquerade:** Add a targeted NAT66/Masquerade option to `router-firewall` for "dirty" but reliable redirection.
3.  **Source-Specific Routing:** Enhance `router-networking` to support routing decisions based on source prefixes, enabling specific LAN segments to exit via VPN.
4.  **Prefix-Watch Sidecar:** Implement a mechanism (via systemd-networkd hooks) to update routing and NPT rules when dynamic prefixes on VPN interfaces change.

**Closure status:** Discussion closed. Transitioning to work-item creation.
