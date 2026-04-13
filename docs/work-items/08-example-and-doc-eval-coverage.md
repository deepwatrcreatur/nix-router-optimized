# 08 Example And Doc Eval Coverage

Status: `done`

Suggested branch: `feat/router-example-doc-eval`

## Goal

Reduce README/docs drift by making more of the documented router module usage
evaluate in CI.

## Why This Matters

The repo has good module docs, but right now examples are mostly static text.
That makes it easy for option names or expected composition patterns to drift
without immediate feedback.

## Scope

- identify the highest-value documented examples in:
  - [`README.md`](../../README.md)
  - [`docs/router-wireguard.md`](../../docs/router-wireguard.md)
  - [`docs/router-openvpn.md`](../../docs/router-openvpn.md)
  - [`docs/router-tailscale.md`](../../docs/router-tailscale.md)
- convert the most important ones into evaluation fixtures or minimal configs
- keep the fixtures small and purpose-built

## Suggested Priorities

- one example for each VPN wrapper module
- one example for the default module bundle
- one example for a router + firewall composition path

## Non-Goals

- parsing markdown automatically in the first version
- exhaustive coverage for every code block

## Validation

- at least a few README/docs examples become CI-backed
- future doc updates have a clearer pattern to follow when adding examples
