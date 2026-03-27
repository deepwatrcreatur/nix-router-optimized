# Caddy reverse proxy with automatic HTTPS
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.caddy-router;

  siteModule = types.submodule {
    options = {
      subdomain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "grafana";
        description = "Optional subdomain for this site. Leave null and set host for arbitrary names.";
      };

      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "grafana.example.com";
        description = "Optional fully-qualified host name for this site.";
      };

      upstream = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://localhost:3000";
        description = "Upstream service URL. Leave null when using redirectTo or custom extraConfig only.";
      };

      redirectTo = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://status.example.com";
        description = "Optional redirect target instead of reverse proxying.";
      };

      access = mkOption {
        type = types.enum [ "public" "trusted" ];
        default = "public";
        description = "Whether the site is public or restricted to trusted client CIDRs.";
      };

      trustedCidrs = mkOption {
        type = types.listOf types.str;
        default = [ "10.0.0.0/8" "100.64.0.0/10" "192.168.0.0/16" ];
        description = "Client CIDRs allowed when access = trusted.";
      };

      deniedResponse = mkOption {
        type = types.str;
        default = "Access restricted";
        description = "HTTP 403 response body used for trusted-only sites.";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Caddy configuration for this site.";
      };
    };
  };

  siteHost = site:
    if site.host != null then
      site.host
    else if site.subdomain != null then
      "${site.subdomain}.${cfg.domain}"
    else
      throw "caddy-router site requires either host or subdomain";

  mkSiteConfig = site:
    let
      backendAction =
        if site.redirectTo != null then
          "redir ${site.redirectTo} permanent"
        else if site.upstream != null then
          "reverse_proxy ${site.upstream}"
        else
          "";

      trustedMatcher =
        "@trusted remote_ip ${concatStringsSep " " site.trustedCidrs}";
    in
    if site.access == "trusted" then
      ''
        ${trustedMatcher}
        handle @trusted {
          ${backendAction}
          ${site.extraConfig}
        }

        respond "${site.deniedResponse}" 403
      ''
    else
      ''
        ${backendAction}
        ${site.extraConfig}
      '';
in {
  options.services.caddy-router = {
    enable = mkEnableOption "Caddy reverse proxy for router services";
    
    domain = mkOption {
      type = types.str;
      example = "example.com";
      description = "Primary domain name for automatic HTTPS";
    };
    
    email = mkOption {
      type = types.str;
      example = "admin@example.com";
      description = "Email for Let's Encrypt certificate notifications";
    };
    
    services = mkOption {
      type = types.attrsOf siteModule;
      default = {};
      description = "Named virtual hosts to proxy or redirect.";
    };

    rootRedirect = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional redirect target for the bare domain.";
    };

    rootResponse = mkOption {
      type = types.str;
      default = "Router Dashboard";
      description = "Fallback response body for the bare domain when rootRedirect is null.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra global Caddy configuration";
    };
  };

  config = mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = cfg.email;
      
      globalConfig = ''
        # Global options
        auto_https on
        ${cfg.extraConfig}
      '';
      
      virtualHosts = 
        # Main domain - redirect to default service or show landing page
        {
          "${cfg.domain}".extraConfig = ''
            ${if cfg.rootRedirect != null then "redir ${cfg.rootRedirect} permanent" else "respond \"${cfg.rootResponse}\" 200"}
          '';
        } //
        # Service subdomains
        (mapAttrs (name: service: {
          "${siteHost service}".extraConfig = mkSiteConfig service;
        }) cfg.services);
    };

    # Open HTTP/HTTPS ports
    networking.firewall.allowedTCPPorts = mkIf (config.networking.firewall.enable) [ 80 443 ];
  };
}
