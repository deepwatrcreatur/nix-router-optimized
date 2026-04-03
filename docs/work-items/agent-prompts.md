# Agent Prompts

Use these prompts to dispatch other agents onto the queue.

## Prompt 1

Read [`docs/work-items/START-HERE.md`](./START-HERE.md) and take the
highest-priority item still marked `Status: \`ready\``. Keep the work to one
PR and update the item status in your branch.

## Prompt 2

Implement [`01-router-ddns-module-inadyn.md`](./01-router-ddns-module-inadyn.md).
Add a thin `router-ddns` module using `inadyn` as the single initial backend.
Do not build a multi-backend abstraction in the first version. Start by
studying the existing Cloudflare DDNS behavior in `unified-nix-configuration`
so the work is an extraction/refactor path, not greenfield invention.

## Prompt 3

Implement [`02-router-ddns-provider-shape.md`](./02-router-ddns-provider-shape.md).
Define a provider-aware but small option shape, starting with practical public
DNS use cases and explicit secret-file handling. Base the first shape on the
current Cloudflare usage in the main config repo.

## Prompt 4

Implement [`03-router-ddns-tests-and-docs.md`](./03-router-ddns-tests-and-docs.md).
Add the first checks and docs needed to make the DDNS module usable by flake
consumers without relying on chat history.

## Prompt 5

Implement [`05-flake-checks-foundation.md`](./05-flake-checks-foundation.md).
Add the first general `checks` structure for this flake so future router module
tests have a clear home in CI.

## Prompt 6

Implement [`06-vpn-module-smoke-tests.md`](./06-vpn-module-smoke-tests.md).
Add smoke coverage for `router-wireguard`, `router-openvpn`, and
`router-tailscale`, focusing on evaluation and the biggest silent-no-op risks.

## Prompt 7

Implement [`07-interface-and-firewall-invariants.md`](./07-interface-and-firewall-invariants.md).
Add tests or assertions around WAN/LAN interface derivation and firewall wiring
so router-local assumptions become visible in CI.

## Prompt 8

Implement [`08-example-and-doc-eval-coverage.md`](./08-example-and-doc-eval-coverage.md).
Make the documented module examples more executable so README/docs drift is
caught earlier.
