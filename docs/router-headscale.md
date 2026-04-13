# router-headscale

`router-headscale` is a router-oriented wrapper around the NixOS
`services.headscale` module. Headscale is the self-hosted coordination server
for standard Tailscale clients.

It adds three router-specific behaviors:

- derives `services.headscale.settings.server_url` from a public domain
- optionally adds a `caddy-router` virtual host for automatic HTTPS
- optionally wires `router-tailscale` to the Headscale login server with
  `tailscale up --login-server`

## Example

```nix
{
  imports = [
    router-optimized.nixosModules.caddy-reverse-proxy
    router-optimized.nixosModules.router-headscale
    router-optimized.nixosModules.router-tailscale
  ];

  services.caddy-router = {
    enable = true;
    domain = "example.com";
    email = "admin@example.com";
  };

  services.router-headscale = {
    enable = true;
    domain = "headscale.example.com";
  };

  services.router-tailscale = {
    enable = true;
    authKeyFile = "/run/agenix/headscale-preauth-key";
  };
}
```

With `services.caddy-router.enable = true`, Headscale listens on
`127.0.0.1:8080` and Caddy proxies `https://headscale.example.com` to it. If
`router-firewall` is also enabled, the module opens TCP 80/443 through
`services.router-firewall.wanTcpPorts`.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the module |
| `domain` | `null` | Public Headscale hostname |
| `controlServerUrl` | `null` | Client login URL; defaults to `https://<domain>` |
| `address` | `null` | Internal bind address; defaults to loopback with Caddy, otherwise all interfaces |
| `port` | `8080` | Internal Headscale listen port |
| `settings` | `{}` | Extra `services.headscale.settings` |
| `openFirewall` | `true` | Expose the public endpoint |
| `useCaddy` | `true` | Add a Caddy vhost when caddy-router is enabled |
| `caddyAccess` | `"public"` | Caddy access policy |
| `caddyTrustedCidrs` | private/Tailscale CIDRs | Client CIDRs for trusted-only Caddy access |
| `caddyDeniedResponse` | `"Access restricted"` | HTTP 403 body for trusted-only Caddy access |

## Join Workflow

Deploy Headscale first, then create a pre-auth key on the router:

```bash
headscale users create homelab
headscale preauthkeys create --user homelab --reusable --expiration 24h
```

Store the generated key in your secret manager and point
`services.router-tailscale.authKeyFile` at the decrypted file. When
`router-headscale` and `router-tailscale` are both enabled, this module appends
`--login-server=https://<domain>` to `services.tailscale.extraUpFlags`.

## HTTPS

Headscale clients require a trusted HTTPS endpoint. The preferred router setup
is to enable `caddy-reverse-proxy` and let Caddy handle certificates:

```nix
services.caddy-router.enable = true;
services.router-headscale.useCaddy = true;
```

If you disable Caddy, configure TLS directly through
`services.router-headscale.settings` / `services.headscale.settings` and expose
the direct Headscale port:

```nix
services.router-headscale = {
  enable = true;
  domain = "headscale.example.com";
  useCaddy = false;
  port = 443;
  settings = {
    tls_cert_path = "/run/agenix/headscale.crt";
    tls_key_path = "/run/agenix/headscale.key";
  };
};
```
