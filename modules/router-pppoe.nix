{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-pppoe;
  hasRouterOption = path: hasAttrByPath path options;

  pppoeConfig = concatStringsSep "\n" (
    [
      "plugin rp-pppoe.so ${cfg.physicalDevice}"
      "ifname ${cfg.interfaceName}"
      "user \"${cfg.username}\""
      "hide-password"
      "noauth"
      "persist"
      "maxfail 0"
      "mtu ${toString cfg.mtu}"
      "mru ${toString cfg.mru}"
    ]
    ++ optionals cfg.defaultRoute [ "defaultroute" ]
    ++ optionals cfg.usePeerDns [ "usepeerdns" ]
    ++ optionals cfg.enableIpv6 [ "+ipv6" ]
    ++ optionals (cfg.serviceName != null) [ "rp_pppoe_service ${cfg.serviceName}" ]
    ++ optionals (cfg.accessConcentrator != null) [ "rp_pppoe_ac ${cfg.accessConcentrator}" ]
    ++ optionals (cfg.credentialsFile != null) [ "file ${cfg.credentialsFile}" ]
    ++ optionals (cfg.extraConfig != "") [ cfg.extraConfig ]
  );
in
{
  options.services.router-pppoe = {
    enable = mkEnableOption "PPPoE uplink wrapper for NixOS routers";

    peerName = mkOption {
      type = types.str;
      default = "wan";
      description = "Name of the underlying pppd peer.";
    };

    interfaceName = mkOption {
      type = types.str;
      default = "ppp0";
      description = "PPP interface name created by pppd.";
    };

    physicalDevice = mkOption {
      type = types.str;
      description = "Underlying ethernet interface used for PPPoE discovery.";
    };

    username = mkOption {
      type = types.str;
      description = "PPPoE username.";
    };

    credentialsFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional runtime path to additional pppd directives such as
        `password "secret"` or secret-file includes. This keeps secrets out of
        the Nix store.
      '';
    };

    serviceName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional PPPoE service name.";
    };

    accessConcentrator = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional PPPoE access concentrator name.";
    };

    mtu = mkOption {
      type = types.int;
      default = 1492;
      description = "MTU for the PPPoE session.";
    };

    mru = mkOption {
      type = types.int;
      default = 1492;
      description = "MRU for the PPPoE session.";
    };

    defaultRoute = mkOption {
      type = types.bool;
      default = true;
      description = "Install the PPPoE session as the default route.";
    };

    usePeerDns = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to accept DNS settings from the PPPoE peer.";
    };

    enableIpv6 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable IPv6CP on the PPPoE session.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional raw pppd lines appended to the peer configuration.";
    };
  };

  config = mkIf cfg.enable {
    services = {
      pppd = {
        enable = true;
        peers.${cfg.peerName} = {
          enable = true;
          autostart = true;
          config = pppoeConfig;
        };
      };
    } // optionalAttrs (hasRouterOption [ "services" "router-networking" "wan" ]) {
      router-networking.wan = {
        device = mkDefault cfg.interfaceName;
        manageWithNetworkd = mkDefault false;
      };
    };
  };
}
