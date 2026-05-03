## Discussion 02: Standards vs. Pragmatism in IPv6 Redirection

**Topic:** Responding to the critique that NAT66/NPTv6 are non-standard or discouraged in the IPv6 community. Should we adopt "pure" solutions or defend our pragmatic approach for travel routers?

### DeepSeek

**The "Pure" Alternative — DHCPv6-PD over VPN:** If we want to avoid NAT/NPT entirely, the standard way is to treat the VPN tunnel as a virtual upstream and run DHCPv6-PD over it. The remote site delegates a prefix to our router, which we then assign to a local VLAN.
- **Problem:** This requires the remote VPN server (and its ISP) to support sub-delegation. For a travel router connecting to a home Tailscale node or a commercial VPN, this is almost never available.
- **The SADR Defense:** Source Address Dependent Routing (SADR) is the "standard" kernel-level way to handle multiple prefixes. If we don't translate the address, the client must have two GUAs: one from the local ISP and one from the VPN. The router then uses SADR to pick the exit. But getting clients (like an Apple TV) to manage two GUAs and pick the right one for specific apps is a nightmare. `[inferred]`

[satisfied]

### Gemini

**The Pragmatic Defense of NPTv6:** We should distinguish between NAT66 (stateful, port-mangling) and NPTv6 (RFC 6296, 1:1 prefix translation).
- **NPTv6 is a "Standard" (Experimental):** While purists dislike it, RFC 6296 exists specifically for address independence without the downsides of stateful NAT. 
- **User Sovereignty:** For a travel router, the user has zero control over the upstream network. NPTv6 is the only mechanism that allows a user to keep a stable internal network (ULA) while "cloaking" it behind whatever dynamic garbage the hotel or VPN provides. I defend the NPTv6 module as a necessary tool for **Sovereign Portability**. `[observed]`

[satisfied]

### GitHub Copilot

**Consistency with the "Optimized" Label:** This flake is called `nix-router-optimized`. Optimization sometimes means choosing the most reliable path for the user over the most theoretical path for the protocol. 
- **New Solution — Provisioning Domains (PvDs):** RFC 8028 introduces PvDs to tell clients "this prefix goes with this DNS and this gateway." It's the standard way forward, but client support is still spotty (mostly limited to modern Android/iOS and some Linux).
- **Verdict:** We should keep NPTv6 but label it as a "Compatibility & Portability" feature. We can add PvD support later as a "Standard-Purity" feature for users with modern clients.

[satisfied]

### Codex

**The Implementation Reality — `ip -6 rule` is the core:** Whether we use NPTv6 or "Pure" SADR, the kernel implementation is remarkably similar.
- **Defense:** Even if we don't use NAT, we still need the **Policy Routing** work item (Item 25). PBR is how we force a prefix to a specific interface.
- **Refinement:** If we want to be "pure," we can implement **Source-Specific Address Selection** hooks. The router can send RAs (Router Advertisements) with the VPN prefix, and if the client uses it, the router sends it down the tunnel. This is "NAT-less" but requires the VPN to allow prefix sub-delegation, which brings us back to DeepSeek's point about it being rare. `[observed]`

[satisfied]

### Synthesis — Q02

**Conclusion: Pragmatism Wins for Travel Routers.**
The agents agree that while "Pure" IPv6 (DHCPv6-PD + SADR) is the ideal, it is technically impossible in many travel router scenarios where the upstream is hostile or limited.

**Strategic Pivot:**
1.  **Re-brand NAT66:** We will call the feature `ipv6Masquerade` and mark it as "Legacy/Geo-Unblocking Compatibility."
2.  **Uphold NPTv6:** We will proceed with `router-nptv6` as our primary recommendation for site-to-site and travel use, citing RFC 6296 as the guiding (though experimental) standard.
3.  **Future-Proofing:** We will add a future work item for **RFC 8028 (Provisioning Domains)** to support NAT-less redirection for modern, PvD-aware clients.
4.  **Requirement Update:** Ensure Work Item 25 (Policy Routing) remains a priority, as it is required for both the "pure" and "pragmatic" solutions.

**Closure status:** Closed. Re-affirming the value of NPTv6 and Policy Routing for the NixOS router ecosystem.
