# Basic Home Router Example

This file is kept as a compatibility pointer for readers who look in
`examples/` first.

For the current recommended non-HA starting point, use:

- [`router-single-basic.nix`](./router-single-basic.nix) for the copyable
  service-level example
- [`../docs/router-single-router-guide.md`](../docs/router-single-router-guide.md)
  for flake wiring, first-boot validation, and what not to enable yet

Why this changed:

- the older version of this file mixed a basic router bring-up with optional
  homelab/monitoring extras
- that made the “simple” path harder to follow for non-specialist users
- the repo now treats the single-router, non-HA path as the default place to
  start

If you want a two-node failover setup instead, skip this file and read:

- [`../docs/router-ha-pair-guide.md`](../docs/router-ha-pair-guide.md)
