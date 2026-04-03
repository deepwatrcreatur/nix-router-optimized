# Agent Prompts

Use these prompts to dispatch other agents onto the queue.

## Prompt 1

Read [`docs/work-items/START-HERE.md`](./START-HERE.md) and take the
highest-priority item still marked `Status: \`ready\``. Keep the work to one
PR and update the item status in your branch.

## Prompt 2

Implement [`01-router-ddns-module-inadyn.md`](./01-router-ddns-module-inadyn.md).
Add a thin `router-ddns` module using `inadyn` as the single initial backend.
Do not build a multi-backend abstraction in the first version.

## Prompt 3

Implement [`02-router-ddns-provider-shape.md`](./02-router-ddns-provider-shape.md).
Define a provider-aware but small option shape, starting with practical public
DNS use cases and explicit secret-file handling.

## Prompt 4

Implement [`03-router-ddns-tests-and-docs.md`](./03-router-ddns-tests-and-docs.md).
Add the first checks and docs needed to make the DDNS module usable by flake
consumers without relying on chat history.
