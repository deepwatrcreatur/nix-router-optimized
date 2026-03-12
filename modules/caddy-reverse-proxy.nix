# Caddy reverse proxy with automatic HTTPS
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.caddy-router;
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
      type = types.attrsOf (types.submodule {
        options = {
          subdomain = mkOption {
            type = types.str;
            example = "grafana";
            description = "Subdomain for this service";
          };
          
          upstream = mkOption {
            type = types.str;
            example = "http://localhost:3000";
            description = "Upstream service URL";
          };
          
          extra-config = mkOption {
            type = types.lines;
            default = "";
            description = "Extra Caddy configuration for this service";
          };
        };
      });
      default = {};
      description = "Services to proxy";
    };
    
    extra-config = mkOption {
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
        ${cfg.extra-config}
      '';
      
      virtualHosts = 
        # Main domain - redirect to default service or show landing page
        {
          "${cfg.domain}".extraConfig = ''
            respond "Router Dashboard" 200
          '';
        } //
        # Service subdomains
        (mapAttrs (name: service: {
          "${service.subdomain}.${cfg.domain}".extraConfig = ''
            reverse_proxy ${service.upstream}
            ${service.extra-config}
          '';
        }) cfg.services);
    };

    # Open HTTP/HTTPS ports
    networking.firewall.allowedTCPPorts = mkIf (config.networking.firewall.enable) [ 80 443 ];
  };
}
