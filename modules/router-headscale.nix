{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-headscale;
  hasRouterOption = path: hasAttrByPath path options;

  caddyRouterEnabled =
    if hasRouterOption [ "services" "caddy-router" "enable" ] then
      (config.services.caddy-router.enable or false)
    else
      false;

  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;

  tailscaleEnabled =
    if hasRouterOption [ "services" "router-tailscale" "enable" ] then
      config.services.router-tailscale.enable
    else
      false;

  effectiveUseCaddy = cfg.useCaddy && caddyRouterEnabled && cfg.domain != null;
  effectiveAddress =
    if cfg.address != null then
      cfg.address
    else if effectiveUseCaddy then
      "127.0.0.1"
    else
      "0.0.0.0";
  effectiveControlServerUrl =
    if cfg.controlServerUrl != null then
      cfg.controlServerUrl
    else if cfg.domain != null then
      "https://${cfg.domain}"
    else
      null;
  firewallTcpPorts = if effectiveUseCaddy then [ 80 443 ] else [ cfg.port ];
  caddyTrustedMatcher = "@trusted remote_ip ${concatStringsSep " " cfg.caddyTrustedCidrs}";
  caddyProxyConfig =
    if cfg.caddyAccess == "trusted" then
      ''
        ${caddyTrustedMatcher}
        handle @trusted {
          reverse_proxy http://127.0.0.1:${toString cfg.port}
        }

        respond "${cfg.caddyDeniedResponse}" 403
      ''
    else
      ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
in
{
  options.services.router-headscale = {
    enable = mkEnableOption "router-aware Headscale defaults";

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "headscale.example.com";
      description = "Public hostname for the Headscale server.";
    };

    controlServerUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://headscale.example.com";
      description = ''
        URL that Tailscale clients use for Headscale. Defaults to
        https://<domain> when domain is set.
      '';
    };

    address = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "127.0.0.1";
      description = ''
        Internal Headscale listen address. Defaults to 127.0.0.1 when Caddy
        integration is active and 0.0.0.0 otherwise.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Internal Headscale listen port.";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Additional settings merged into services.headscale.settings.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Expose the public Headscale endpoint. When Caddy integration is active,
        this opens TCP 80/443 through router-firewall. Otherwise it opens the
        direct Headscale port.
      '';
    };

    useCaddy = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Add a caddy-router virtual host when caddy-reverse-proxy is imported
        and services.caddy-router.enable is true.
      '';
    };

    caddyAccess = mkOption {
      type = types.enum [ "public" "trusted" ];
      default = "public";
      description = "caddy-router access policy for the Headscale endpoint.";
    };

    caddyTrustedCidrs = mkOption {
      type = types.listOf types.str;
      default = [ "10.0.0.0/8" "100.64.0.0/10" "192.168.0.0/16" ];
      description = "Client CIDRs allowed when caddyAccess = trusted.";
    };

    caddyDeniedResponse = mkOption {
      type = types.str;
      default = "Access restricted";
      description = "HTTP 403 response body used when caddyAccess = trusted.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = effectiveControlServerUrl != null;
        message = "services.router-headscale requires either domain or controlServerUrl.";
      }
    ];

    services = {
      headscale = {
        enable = mkDefault true;
        address = mkDefault effectiveAddress;
        port = mkDefault cfg.port;
        settings = mkMerge [
          {
            server_url = mkDefault effectiveControlServerUrl;
            dns = {
              magic_dns = mkDefault false;
              override_local_dns = mkDefault false;
            };
          }
          cfg.settings
        ];
      };
    }
    // optionalAttrs (hasRouterOption [ "services" "caddy-router" "enable" ]) {
      caddy.virtualHosts.${cfg.domain}.extraConfig = mkIf effectiveUseCaddy caddyProxyConfig;
    }
    // optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      router-firewall = mkIf (firewallEnabled && cfg.openFirewall) {
        wanTcpPorts = firewallTcpPorts;
      };
    }
    // optionalAttrs (hasRouterOption [ "services" "router-tailscale" "enable" ]) {
      router-tailscale = mkIf (tailscaleEnabled && effectiveControlServerUrl != null) {
        extraUpFlags = mkAfter [ "--login-server=${effectiveControlServerUrl}" ];
      };
    };

    networking.firewall.allowedTCPPorts =
      mkIf (cfg.openFirewall && !effectiveUseCaddy && !firewallEnabled) [ cfg.port ];
  };
}
