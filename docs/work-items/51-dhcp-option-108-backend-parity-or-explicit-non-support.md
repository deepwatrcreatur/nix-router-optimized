# 51 - DHCP Option 108 Backend Parity or Explicit Non-Support

## Status: `in-progress`

## Objective

Decide, and then encode honestly, what should happen for DHCP option `108` on
the repo's other DHCP backends besides Kea:

- `router-dhcp` (systemd-networkd)
- `router-technitium`

The goal is either bounded support where practical, or explicit non-support with
clear operator guidance where the backend surface is too limited or awkward.

## Rationale

The repo already exposes multiple DHCP backends for different operator needs.
If option `108` lands only on Kea, that may be totally acceptable — but the
boundary needs to be explicit.

The wrong outcome would be a half-implied feature where:

- one backend supports it declaratively
- another silently cannot
- and users have to discover the difference by reading module source

This item exists to settle that backend split deliberately.

## Requirements

- [ ] Evaluate whether `router-dhcp` can support RFC 8925 option `108`
      declaratively through systemd-networkd's DHCP server surface
- [ ] Evaluate whether `router-technitium` can support RFC 8925 option `108`
      through the current synchronization/API model
- [ ] For each backend, choose one of:
      - implement bounded support
      - expose an explicit unsupported assertion/message
      - document a manual escape hatch if that is the most honest interim stance
- [ ] Update docs and module messaging so operators can see backend parity gaps
      without source diving

## Verification

- [ ] For every DHCP backend exported by the repo, option `108` has an explicit
      stance: supported, unsupported, or manual-only
- [ ] No backend quietly ignores an option `108` declarative setting
- [ ] The resulting backend split is documented in the DHCP selection guidance

## Notes

This item is about **backend parity and explicit boundaries**, not about making
every backend feature-identical at any cost.

It is acceptable for the result to be:

- Kea supports it first-class
- other backends do not

as long as that outcome is made obvious and does not create confusing silent
behavior.
