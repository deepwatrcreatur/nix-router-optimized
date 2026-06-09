# Router Runtime Credential Discipline

This note records the current credential-passing boundary across the router
modules that commonly need secrets at runtime.

The rule is narrow:

- prefer runtime files or equivalent protected runtime materialization
- avoid passing secret values in process arguments
- avoid broad environment-variable secret injection
- avoid embedding live credentials in store-backed config when a runtime-file
  path already fits the upstream service

## Current Audit Outcome

### Already Aligned

- `router-wireguard`
  uses `privateKeyFile` and optional peer `presharedKeyFile` runtime paths.
- `router-tailscale`
  threads `authKeyFile` through to upstream Tailscale as a runtime file path.
- `router-netbird`
  threads `setupKeyFile` and dependency ordering through to the upstream login
  block as a runtime file path.
- `router-cloudflare-tunnel`
  expects `credentialsFile` and optional `certificateFile` paths rather than
  embedding tunnel credentials.
- `router-ddns`
  reads a raw Cloudflare token from `cloudflare.apiTokenFile` at runtime and
  materializes a narrow inadyn include file under `/run/router-ddns`.
- `router-dashboard`
  reads mutation authorization from `mutationAuth.tokenFile` and Technitium API
  access from runtime token files; the dashboard environment contains file paths
  only, not the secret values themselves.
- `router-pppoe`
  keeps password-like directives in `credentialsFile`, leaving the main peer
  config free of embedded secrets.

### Tightened By This Audit

- `router-bgp`
  already used per-neighbor `passwordFile` paths and a runtime placeholder
  replacement step. This audit removes the remaining argv exposure in that
  replacement helper by staging the secret in a short-lived `/run/frr` file
  instead of passing the secret value as a process argument.

### Needs Follow-On Tightening

- `router-openvpn`
  keeps the right overall boundary for certificates and keys when operators put
  those paths in raw OpenVPN config, but the passthrough `authUserPass` option
  can still encourage direct username/password embedding in Nix values. Prefer
  `auth-user-pass /run/...` in `config` today. A follow-on change can narrow or
  replace `authUserPass` with an explicit runtime-file-first surface.

### Intentionally Different Safe Pattern

- `router-technitium`
  manages its API token as a private runtime artifact under
  `/var/lib/private/technitium-dns-server` instead of `/run`. That is still
  consistent with the repo rule because the secret is generated or copied at
  runtime and then consumed from a protected on-host file rather than embedded
  in the store or process arguments.

## Practical Guidance

- When an upstream module already supports `*File` options, use those directly.
- When an upstream module expects inline config, prefer a runtime include file or
  a start-time materialization step under `/run`.
- If you add a new router wrapper around a service with credentials, document
  where the secret lives at runtime and how it avoids argv or broad environment
  exposure.
