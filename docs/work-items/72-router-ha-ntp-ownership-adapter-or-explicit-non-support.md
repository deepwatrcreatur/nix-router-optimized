# 72 - Router HA NTP Ownership Adapter or Explicit Non-Support

## Status: `done`

## Objective

Decide whether LAN-facing NTP service ownership deserves a first-class
`router-ha` adapter, or whether it should remain explicitly outside upstream
promotion-aware ownership for now.

## Rationale

Items `67` and `68` introduced a bounded HA ownership model and the first typed
adapters.

That left a real follow-up question:

- should `chronyd` or the repo's router-NTP surface become a typed ownership
  adapter
- or is the service semantics still too deployment-specific to upstream safely

## Requirements

- [x] Decide whether NTP is a strong candidate for a typed adapter or should
      remain generic/consumer-owned
- [x] If not supported, document that boundary explicitly so operators do not
      infer broader HA ownership than exists
- [x] Add eval/docs coverage for the chosen stance

## Verification

- [x] Operators can tell whether NTP ownership is upstream-supported, generic,
      or explicitly unsupported
- [x] The repo still avoids implying universal promotion-aware service
      orchestration

## Outcome

The repo now makes the NTP stance explicit:

- no typed `router-ha` adapter for `router-ntp`
- no upstream claim that Keepalived `notify_*` transitions are the correct
  universal Chrony ownership model
- NTP remains generic consumer policy if operators want to gate a time-service
  unit manually

This is intentionally a non-support decision for the typed adapter layer, not a
claim that NTP is unimportant under HA.

## Notes

This item is about **NTP service ownership semantics under HA**, not general
time-service redesign.
