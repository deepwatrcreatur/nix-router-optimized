{
  config,
  lib,
  pkgs,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-pangolin;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
in
{
  options.services.router-pangolin = {
    enable = mkEnableOption "router-aware Pangolin tunnel/reverse proxy integration";

    baseDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Base domain for Pangolin tunnel endpoints.";
    };

    dashboardDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Dashboard domain for Pangolin management interface.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to environment file containing secrets for Pangolin.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically open required ports in router-firewall / system firewall.";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Additional configuration settings for Pangolin.";
    };
  };

  config = mkIf cfg.enable {
    services.pangolin = {
      enable = true;
      baseDomain = cfg.baseDomain;
      dashboardDomain = cfg.dashboardDomain;
      environmentFile = cfg.environmentFile;
      openFirewall = cfg.openFirewall;
      settings = cfg.settings;
    };

    services.router-firewall = mkIf (firewallEnabled && cfg.openFirewall) {
      wanTcpPorts = [ 80 443 ];
    };
  };
}
