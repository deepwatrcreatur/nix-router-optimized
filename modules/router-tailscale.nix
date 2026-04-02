{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.router-tailscale;
  firewallEnabled = config.services.router-firewall.enable or false;
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
      type = types.nullOr types.path;
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
    services.tailscale = {
      enable = true;
      interfaceName = cfg.interfaceName;
      port = cfg.port;
      authKeyFile = cfg.authKeyFile;
      useRoutingFeatures = routingMode;
      extraUpFlags = upFlags;
      extraSetFlags = cfg.extraSetFlags;
      extraDaemonFlags = cfg.extraDaemonFlags;
      openFirewall = mkDefault (!firewallEnabled && cfg.openFirewall);
    };

    services.router-firewall = mkIf firewallEnabled {
      tailscaleInterface = mkIf cfg.trustedInterface cfg.interfaceName;
      wanUdpPorts = mkIf cfg.openFirewall [ cfg.port ];
    };
  };
}
