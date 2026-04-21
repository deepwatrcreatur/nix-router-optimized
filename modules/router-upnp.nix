{ config, options, lib, ... }:

with lib;

let
  cfg = config.services.router-upnp;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  hasRouterNetworking = hasAttrByPath [ "services" "router-networking" "wan" "device" ] options;
in
{
  options.services.router-upnp = {
    enable = mkEnableOption "MiniUPnPd with secure defaults and nftables integration";

    externalInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "External WAN interface. If null, derived from router-networking.";
    };

    internalIPs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "enp6s16" "10.10.0.1/16" ];
      description = "Internal interfaces or IP ranges to listen on for UPnP requests.";
    };

    secureMode = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When enabled, clients can only map ports to their own IP address.
        Strongly recommended for security.
      '';
    };

    natpmp = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NAT-PMP (Apple's version of UPnP).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.miniupnpd = {
        enable = true;
        externalInterface =
          if cfg.externalInterface != null then cfg.externalInterface
          else if hasRouterNetworking then config.services.router-networking.wan.device
          else mkDefault "";
        internalIPs = cfg.internalIPs;
        natpmp = cfg.natpmp;
        upnp = true;
        appendConfig = optionalString cfg.secureMode "secure_mode=yes";
      };
    }

    (if hasRouterFirewall then {
      services.router-firewall.extraForwardRules = mkIf (
        config.services.router-firewall.enable or false
      ) ''
        ct status dnat accept comment "Allow UPnP/NAT-PMP forwarded traffic"
      '';
    } else {})
  ]);
}
