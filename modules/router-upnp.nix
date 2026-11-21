{ config, options, lib, ... }:

with lib;

let
  cfg = config.services.router-upnp;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  hasRouterNetworking = hasAttrByPath [ "services" "router-networking" "wan" "device" ] options;
  hasRouterHa = options ? services.router-ha.singleActiveUnits;
  routerHaEnabled = hasRouterHa && (config.services.router-ha.enable or false);
  manualHaUnit = hasRouterHa && (elem "miniupnpd.service" config.services.router-ha.singleActiveUnits || elem "miniupnpd" config.services.router-ha.singleActiveUnits);
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

    ha.singleActiveOwner = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run miniupnpd only on the VRRP MASTER. It is not started at boot;
        `services.router-ha` starts it on promotion and stops it on backup or
        fault. Port mappings do not move: clients re-request them after a
        failover. Requires `services.router-ha.enable`.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          # WHY: a backup miniupnpd answers SSDP on the LAN and installs
          # mappings for a WAN it does not hold.
          assertion = !routerHaEnabled || cfg.ha.singleActiveOwner || manualHaUnit;
          message = ''
            services.router-upnp with services.router-ha needs explicit ownership. Set
              services.router-upnp.ha.singleActiveOwner = true;
            so miniupnpd runs only on the VRRP MASTER.
          '';
        }
        {
          assertion = cfg.ha.singleActiveOwner -> routerHaEnabled;
          message = "services.router-upnp.ha.singleActiveOwner requires services.router-ha.enable = true.";
        }
      ];

      warnings = optional (routerHaEnabled && !cfg.ha.singleActiveOwner && manualHaUnit) ''
        services.router-upnp: miniupnpd.service is listed in services.router-ha.singleActiveUnits
        by hand. Set services.router-upnp.ha.singleActiveOwner = true instead; it also
        keeps miniupnpd from starting at boot on the backup.
      '';

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

    (mkIf cfg.ha.singleActiveOwner {
      # INVARIANT: only router-ha notify_master starts miniupnpd.
      systemd.services.miniupnpd.wantedBy = mkForce [ ];
    })

    (optionalAttrs hasRouterHa {
      services.router-ha.singleActiveUnits = mkIf cfg.ha.singleActiveOwner [ "miniupnpd.service" ];
    })

    (if hasRouterFirewall then {
      services.router-firewall.extraForwardRules = mkIf (
        config.services.router-firewall.enable or false
      ) ''
        ct status dnat accept comment "Allow UPnP/NAT-PMP forwarded traffic"
      '';
    } else {})
  ]);
}
