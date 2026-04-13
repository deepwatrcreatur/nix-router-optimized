# Router DDNS Provider Shape

`services.router-ddns` is intentionally scoped to public Dynamic DNS updates for
router-hosted ingress names. It does not own local DNS, DHCP registration, or
internal resolver behavior.

## Current Source Model

The initial shape is based on the Cloudflare usage in the main private router
configuration:

- the public zone is a single domain, such as `example.com`
- `router.ddnsServices` is a list of public labels under that zone
- `@` means the zone apex
- labels such as `homelab` and `paperless` expand to full hostnames under the
  public zone
- the Cloudflare token is provided by a runtime secret file
- public ingress inventory remains separate from local/internal DNS inventory

This maps directly to:

```nix
services.router-ddns = {
  enable = true;
  cloudflare = {
    zoneName = "example.com";
    labels = [ "@" "homelab" "paperless" ];
    apiTokenFile = "/run/agenix/cloudflare-ddns-token";
  };
};
```

## Chosen First Provider Shape

The first supported provider is an explicit `cloudflare` submodule, not a
generic provider registry. That keeps the option surface small and avoids
abstracting over provider-specific record semantics before there is a second
real provider to compare against.

The required inputs are:

- `cloudflare.zoneName`: public Cloudflare DNS zone name
- `cloudflare.apiTokenFile`: runtime file containing a raw Cloudflare API token
  string, without quotes; the module writes the quoted inadyn include value at
  service start
- at least one value in `cloudflare.labels` or `cloudflare.hostnames`

The record inputs are:

- `cloudflare.labels`: labels under `zoneName`; `@` expands to the apex
- `cloudflare.hostnames`: fully qualified hostnames for cases that should not
  derive from `zoneName`
- `cloudflare.ttl`: Cloudflare record TTL, defaulting to `3600`; use `1` for
  Cloudflare Automatic TTL
- `cloudflare.proxied`: whether Cloudflare should proxy the records, defaulting
  to `false`

## Integration Boundary

`router-ddns` should consume public ingress inventory, but it should not become
the inventory source of truth itself. A downstream router config can pass
`router.ddnsServices` or equivalent labels into `cloudflare.labels`.

Keep these boundaries:

- Public DDNS is for WAN-reachable public DNS names.
- Local DNS and DHCP-derived host registration belong to resolver/provider
  modules such as `router-dns-service` and `router-technitium`.
- Public reverse proxy routing belongs to the downstream Caddy or ingress
  configuration.
- A downstream config may assert that DDNS labels are a subset of public ingress
  names, but this reusable module should not assume a specific inventory schema.

## Deferred Provider Abstraction

Do not introduce `providers.<name>` or a provider enum until another provider is
being implemented. The likely next step is to factor shared label expansion only
after the second provider proves it needs the same inputs.
