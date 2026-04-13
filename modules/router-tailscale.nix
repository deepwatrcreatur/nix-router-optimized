{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-tailscale;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
  wantsServer = cfg.advertiseRoutes != [ ] || cfg.advertiseExitNode;
  wantsClient = cfg.acceptRoutes;
  routingMode =
    if wantsServer && wantsClient then
      "both"
    else if wantsServer then
      "server"
    else if wantsClient then
      "client"
    else
      "none";

  upFlags =
    optionals (cfg.advertiseRoutes != [ ]) [
      "--advertise-routes=${concatStringsSep "," cfg.advertiseRoutes}"
    ]
    ++ optionals cfg.advertiseExitNode [ "--advertise-exit-node" ]
    ++ optionals cfg.acceptRoutes [ "--accept-routes" ]
    ++ optionals cfg.enableSsh [ "--ssh" ]
    ++ cfg.extraUpFlags;
in
{
  options.services.router-tailscale = {
    enable = mkEnableOption "router-aware Tailscale defaults";

    interfaceName = mkOption {
      type = types.str;
      default = "tailscale0";
      description = "Tailscale interface name exposed to router-firewall.";
    };

    port = mkOption {
      type = types.port;
      default = 41641;
      description = "UDP port used by tailscaled.";
    };

    authKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional auth key file used for automatic tailscale up.";
    };

    advertiseRoutes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.0.0/16" "192.168.100.0/24" ];
      description = "Subnet routes advertised by this router to the tailnet.";
    };

    advertiseExitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Advertise this router as a Tailscale exit node.";
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = false;
      description = "Accept subnet routes advertised by other Tailscale nodes.";
    };

    enableSsh = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Tailscale SSH during tailscale up.";
    };

    trustedInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Treat the Tailscale interface as trusted in router-firewall.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the Tailscale UDP port on WAN when router-firewall is enabled.";
    };

    extraUpFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional tailscale up flags appended after router defaults.";
    };

    extraSetFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra tailscale set flags.";
    };

    extraDaemonFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra tailscaled daemon flags.";
    };
  };

  config = mkIf cfg.enable {
    services = {
      tailscale = {
        enable = mkDefault true;
        interfaceName = mkDefault cfg.interfaceName;
        port = mkDefault cfg.port;
        authKeyFile = mkDefault cfg.authKeyFile;
        useRoutingFeatures = mkDefault routingMode;
        extraUpFlags = mkDefault upFlags;
        extraSetFlags = mkDefault cfg.extraSetFlags;
        extraDaemonFlags = mkDefault cfg.extraDaemonFlags;
        openFirewall = mkDefault (!firewallEnabled && cfg.openFirewall);
      };
    } // optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      router-firewall = mkIf firewallEnabled {
        overlayInterfaces = mkIf cfg.trustedInterface [ cfg.interfaceName ];
        wanUdpPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };
  };
}
