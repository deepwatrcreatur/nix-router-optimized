## Discussion 04: Recovered Security/Zones Work Review

**Status:** closed

**Topic:** Review of the recovered `router-security-hardened` and `router-zones` work after reboot recovery and rebase onto current `main`.

**Context:** The recovered work was isolated onto a clean branch based on current `main` and validated with `nix flake check --no-build`. Evaluation passed, but a code review found several runtime and semantics risks that should be resolved before merge.

### DeepSeek

**The nftables correctness problem:** The current `router-zones` policy rendering can emit an invalid rule when a policy entry does not provide `extraRules`. That is a hard blocker because a malformed ruleset can prevent firewall activation entirely.

**The input/forward split is incomplete:** The module defines `defaultInputPolicy` and generates `zone_*_in` chains, but the only visible dispatch path is through forward handling. That means the design gestures at zone-aware router-local policy without actually implementing it. From a network-engineering perspective, that is worse than omitting the option entirely because it creates a false sense of enforcement. `[observed]`

[satisfied]

### Gemini

**The UX contract is currently misleading:** A user enabling "zones" or "MAC security" will reasonably assume the router itself is protected, not just transit traffic. The present implementation appears to restrict forwarded traffic but leaves router-local access outside the zone and MAC policy path.

**The docs/behavior mismatch matters:** The Geo-IP feature is described as WAN-oriented, but if it executes in the global input chain it can block trusted local clients too. That kind of surprise would be expensive to debug on a live router and should be corrected either in behavior or in naming before release. `[observed]`

[satisfied]

### GitHub Copilot

**The integration seam is promising:** The `extraFilterTableRules` hook in `router-firewall` is the meaningful recovered architectural change. It enables modules to declare shared sets and helper chains rather than only appending per-chain snippets.

**The module contract needs tightening:** Before merge, the new modules should either:
- fully implement input-path enforcement, or
- narrow their public options so they only claim forward-path behavior.

The first release should prefer a minimal, internally consistent surface area over a broader option set that is only partially wired. `[observed]`

[satisfied]

### Codex

**Implementation findings from the recovered branch review:**
- `router-zones` can render an invalid nft rule when `extraRules = ""`, because the generated policy block still emits a line that requires an action.
- `defaultInputPolicy` is dead configuration, and `zone_*_in` chains are not jumped to from the input hook.
- Geo-IP blocking is attached to `extraInputRules`, so it currently applies to all input traffic rather than only WAN input.
- MAC security is attached to `extraForwardRules`, so it does not protect router-local input.
- The Geo-IP updater fetches country lists over plain HTTP, which is not acceptable for a security control that directly feeds firewall blocklists.

**Minimal repair strategy:**
1. Make zone policy rendering conditional so empty `extraRules` does not generate a broken nft statement.
2. Decide whether zone/MAC policy should govern router-local input. If yes, add explicit input-chain dispatch. If no, rename options and docs so the scope is unambiguous.
3. Scope Geo-IP filtering to WAN ingress explicitly instead of attaching it to the generic input chain.
4. Move Geo-IP downloads to HTTPS or another authenticated source before merge. `[observed]`

[satisfied]

### Synthesis — Q04

**Conclusion:** The recovered work contains a useful extension seam in `router-firewall` and plausible first drafts of `router-security-hardened` and `router-zones`, but it is not merge-ready yet.

**Merge blockers:**
1. Invalid nftables output in the default `router-zones` path.
2. Dead or misleading input-policy configuration in `router-zones`.
3. Security feature semantics that do not match their user-facing descriptions.
4. Plain-HTTP Geo-IP source download.

**Recommended next step:**
1. Keep the `router-firewall` extension point.
2. Reduce `router-zones` to a correct forward-only implementation unless input dispatch is completed now.
3. Narrow `router-security-hardened` claims to match actual enforcement scope, or wire input-path protection explicitly.
4. Re-run evaluation and a rendered-ruleset inspection after those repairs.

**Closure status:** Closed. The follow-up implementation pass and validation work were captured after this review; keep this document as the design/review record rather than an active discussion.
