# Private Config Pattern Study

This note reviews the private-configuration pattern in
`joshpearce/nix-router` and identifies what should be borrowed into
`nix-router-optimized` while keeping this flake reusable.

## Upstream Pattern

`joshpearce/nix-router` is an appliance-style router repository. Its
`flake.nix` declares a `private` input that defaults to `path:./private.example`
and is overridden for real deployments with `--override-input private
path:./private`.

The private input exports a NixOS module from `private.example/config.nix` or
`private/config.nix`. That module populates `config.private`, with
`private-options.nix` defining the schema for values such as:

- primary user identity and SSH keys
- public domain and AWS Route53 settings
- healthchecks and Loki endpoints
- extra hosts entries
- an `ip_manifest` inventory used by network, DHCP, and DNS logic

The repository also documents a bootstrap workflow around `make init`,
`make decrypt`, `make encrypt`, and agenix runtime secrets. The decrypted
`private/config.nix` is kept out of Git, while `private/config.nix.age` is
committed for that single-user repo.

## Fit For This Repository

The useful idea is not the exact `config.private` namespace. The useful idea is
the boundary: a router often needs a private deployment inventory, typed
validation, and clear examples for mapping that inventory into reusable modules.

`nix-router-optimized` should keep reusable modules parameterized by their own
public options. For example, `services.router-ddns.cloudflare.labels` should
remain an explicit module option rather than implicitly reading from a global
`config.private.domain` or `config.private.ddnsServices` shape.

Downstream users can still keep their own private flake, host repo, or encrypted
inventory. That downstream layer can import `nix-router-optimized` and map
private values into this flake's module options.

## Recommendation

Borrow now:

- Add example-driven documentation for a downstream private inventory flake
  once there is a concrete consumer-facing example to attach it to.
- Keep typed option schemas at module boundaries. If a downstream inventory
  template is added, make it optional and map it into existing module options
  instead of making every module depend on a shared `config.private` namespace.
- Document the distinction between build-time deployment inventory and runtime
  secrets. Runtime credentials should continue to flow through secret file paths
  such as agenix or sops-nix outputs, not through evaluated Nix strings.

Defer:

- A committed `private.example/` template in this repo. It is useful, but only
  after this flake has a stable example host composition that represents the
  recommended downstream shape.
- A `--override-input private path:./private` workflow. That is appropriate for
  an appliance repo, but it should not become the normal build path for this
  reusable flake.
- Makefile-style decrypt/encrypt automation. This repo should not own users'
  encrypted private inventory unless it intentionally becomes an appliance
  template, which is not the current direction.
- Schema tests for private inventory. Those belong after the flake check
  foundation exists and after an optional inventory example exists.

Reject:

- Requiring modules to read deployment-specific values from `config.private.*`.
  That couples reusable modules to one private inventory schema.
- Committing encrypted private config for this reusable flake. Users' encrypted
  deployment data belongs in their downstream repo or secret store.
- Baking provider-specific personal assumptions, such as AWS-only domains or a
  fixed primary user, into shared module APIs.
- Making a private input override mandatory for normal examples, tests, or
  evaluation.

The practical path is to keep `nix-router-optimized` as a module library with
good examples. If a private inventory helper is added later, it should be a
thin adapter layer rather than a dependency of the reusable modules.
