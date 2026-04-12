{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-dhcp;
  routedIfaces = config.services.router-networking.routedInterfaces or { };

  leaseModule = types.submodule {
    options = {
      macAddress = mkOption {
        type = types.str;
        description = "Static lease MAC address.";
      };

      address = mkOption {
        type = types.str;
        description = "Static lease IPv4 address.";
      };

      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional hostname for this lease. When set, systemd-networkd registers the name in its internal DNS, making the host reachable by name on the segment.";
      };
    };
  };

  dhcpInterfaceModule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable DHCP on this routed segment.";
      };

      poolOffset = mkOption {
        type = types.int;
        default = 100;
        description = "Offset into the subnet where the DHCP pool begins.";
      };

      poolSize = mkOption {
        type = types.int;
        default = 100;
        description = "Number of DHCP leases available in the dynamic pool.";
      };

      defaultLeaseTimeSec = mkOption {
        type = types.int;
        default = 3600;
        description = "Default IPv4 DHCP lease time in seconds.";
      };

      maxLeaseTimeSec = mkOption {
        type = types.int;
        default = 43200;
        description = "Maximum IPv4 DHCP lease time in seconds.";
      };

      dns = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Optional DNS servers to advertise. Defaults to the routed interface DNS list.";
      };

      emitDns = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the DHCP server should advertise DNS servers.";
      };

      emitRouter = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the DHCP server should advertise a default router.";
      };

      staticLeases = mkOption {
        type = types.listOf leaseModule;
        default = [ ];
        description = "Static DHCP leases for this routed segment.";
      };

      pxe = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to advertise PXE boot options on this segment.";
            };

            bootServerAddress = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional PXE boot server address (BootServerAddress=).";
            };

            bootServerName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional PXE boot server name (BootServerName=).";
            };

            bootFilename = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "PXE boot filename or URL (BootFilename=).";
            };
          };
        };
        default = { };
        description = "Typed PXE boot advertisement options for this routed segment.";
      };

      extraDhcpServerConfig = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Additional raw [DHCPServer] settings for systemd-networkd.";
      };
    };
  };

  effectiveInterfaces =
    if cfg.interfaces != { } || !cfg.autoInterfacesFromNetworking then
      filterAttrs (_name: iface: iface.enable) cfg.interfaces
    else
      mapAttrs (_name: iface: {
        enable = true;
        poolOffset = 100;
        poolSize = 100;
        defaultLeaseTimeSec = 3600;
        maxLeaseTimeSec = 43200;
        dns = null;
        emitDns = true;
        emitRouter = true;
        staticLeases = [ ];
        extraDhcpServerConfig = { };
      }) (filterAttrs (_name: iface: elem iface.role cfg.matchRoles) routedIfaces);

  mkDhcpNetwork =
    name: ifaceCfg:
    let
      routedIface = routedIfaces.${name};
      effectiveDns = if ifaceCfg.dns != null then ifaceCfg.dns else routedIface.dns;
      pxeCfg =
        ifaceCfg.pxe or {
          enable = false;
          bootFilename = null;
          bootServerAddress = null;
          bootServerName = null;
        };
      pxeDhcpConfig = optionalAttrs pxeCfg.enable (
        {
          BootFilename = pxeCfg.bootFilename;
        }
        // optionalAttrs (pxeCfg.bootServerAddress != null) {
          BootServerAddress = pxeCfg.bootServerAddress;
        }
        // optionalAttrs (pxeCfg.bootServerName != null) {
          BootServerName = pxeCfg.bootServerName;
        }
      );
    in
    {
      networkConfig.DHCPServer = true;
      dhcpServerConfig = {
        PoolOffset = ifaceCfg.poolOffset;
        PoolSize = ifaceCfg.poolSize;
        DefaultLeaseTimeSec = ifaceCfg.defaultLeaseTimeSec;
        MaxLeaseTimeSec = ifaceCfg.maxLeaseTimeSec;
        EmitRouter = ifaceCfg.emitRouter;
        EmitDNS = ifaceCfg.emitDns && effectiveDns != [ ];
      }
      // optionalAttrs (effectiveDns != [ ]) {
        DNS = effectiveDns;
      }
      // pxeDhcpConfig
      // ifaceCfg.extraDhcpServerConfig;
      dhcpServerStaticLeases = map (
        lease:
        {
          MACAddress = lease.macAddress;
          Address = lease.address;
        }
        // optionalAttrs (lease.hostname != null) { Hostname = lease.hostname; }
      ) ifaceCfg.staticLeases;
    };
in
{
  options.services.router-dhcp = {
    enable = mkEnableOption "router-friendly DHCP defaults for routed interfaces";

    autoInterfacesFromNetworking = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true and no explicit interfaces are defined, enable DHCP on
        routed interfaces from services.router-networking whose roles match
        matchRoles.
      '';
    };

    matchRoles = mkOption {
      type = types.listOf (
        types.enum [
          "lan"
          "management"
          "opt"
        ]
      );
      default = [
        "lan"
        "management"
      ];
      description = "Routed interface roles that receive automatic DHCP service.";
    };

    interfaces = mkOption {
      type = types.attrsOf dhcpInterfaceModule;
      default = { };
      description = "Per-routed-interface DHCP configuration keyed by routed interface name.";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      (mapAttrsToList (name: _ifaceCfg: {
        assertion = hasAttr name routedIfaces;
        message = "router-dhcp.interfaces.${name} requires a matching services.router-networking.routedInterfaces.${name}.";
      }) cfg.interfaces)
      ++ (mapAttrsToList (name: ifaceCfg: {
        assertion = !(ifaceCfg.pxe.enable && ifaceCfg.pxe.bootFilename == null);
        message = "services.router-dhcp.interfaces.${name}.pxe.bootFilename must be set when PXE is enabled.";
      }) cfg.interfaces);

    systemd.network.networks = mapAttrs' (
      name: ifaceCfg: nameValuePair "20-router-${name}" (mkDhcpNetwork name ifaceCfg)
    ) effectiveInterfaces;
  };
}
