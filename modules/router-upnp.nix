{ config, options, lib, ... }:

with lib;

let
  cfg = config.services.router-upnp;
  routedIfaces = config.services.router-networking.routedInterfaces or { };
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  hasRouterNetworking = hasAttrByPath [ "services" "router-networking" "wan" "device" ] options;

  # Auto-derive internal interfaces from router-networking when none are specified.
  effectiveInternalIPs =
    if cfg.internalIPs != [ ] then
      # Strip CIDR masks if provided, as miniupnpd prefers bare interface names or IPs.
      map (i: head (splitString "/" i)) cfg.internalIPs
    else
      mapAttrsToList (_name: iface: iface.device) (
        filterAttrs (_name: iface: elem iface.role [ "lan" ]) routedIfaces
      );
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
      description = ''
        Internal interfaces or IP ranges to listen on for UPnP requests.
        Defaults to LAN-role interfaces from services.router-networking.
      '';
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
        internalIPs = effectiveInternalIPs;
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
