# 36 - Recent Correctness Fixes: Geo-IP and Runtime Token Alignment

## Status: `ready`

## Objective

Finish the two most important targeted correctness fixes surfaced by Discussion
06 without reopening broader architecture questions:

- Geo-IP blocklist refresh correctness in `router-security-hardened`
- Technitium/dashboard runtime token alignment

## Rationale

Discussion 06 concluded that these issues are real and should be fixed quickly,
but they do not justify broad redesign:

- the Geo-IP updater likely needs a safer nft set refresh/update strategy
- the dashboard should follow the same runtime-first Technitium token resolution
  path as the newer `router-technitium` logic

## Requirements

- [ ] Replace the current Geo-IP nft set update approach with a valid and safe
      strategy suitable for periodic refresh
- [ ] Add validation or at least a documented reasoning path for why the chosen
      nft update strategy is correct
- [ ] Ensure dashboard Technitium token loading honors the runtime token path
      before any static/fallback path
- [ ] Add lightweight verification for the dashboard token-path contract if
      possible within the repo's current test style

## Verification

- [ ] Geo-IP refresh no longer depends on a dubious or invalid set replacement
      shape
- [ ] Dashboard DNS/Technitium endpoints can resolve the same live token source
      the Technitium module now prefers
- [ ] The fixes are documented well enough that future contributors do not drift
      the two paths apart again
