{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-networking;

  routeModule = types.submodule {
    options = {
      destination = mkOption {
        type = types.str;
        description = "Route destination, for example 10.10.0.0/16.";
      };

      scope = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional route scope.";
      };
    };
  };

  routedInterfaceModule = types.submodule {
    options = {
      device = mkOption {
        type = types.str;
        description = "Interface device name, for example ens16.";
      };

      ipv4Address = mkOption {
        type = types.str;
        description = "Primary IPv4 CIDR address for the routed segment.";
      };

      role = mkOption {
        type = types.enum [ "lan" "management" "opt" ];
        default = "lan";
        description = "Logical role for documentation and future consumers.";
      };

      prefixDelegationMode = mkOption {
        type = types.enum [ "slaac" "managed" ];
        default = "slaac";
        description = "Whether the segment should advertise SLAAC-only or managed DHCPv6-style RAs.";
      };

      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DNS servers to advertise on the routed segment.";
      };

      domains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Search domains to advertise on the routed segment.";
      };

      requiredForOnline = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional systemd-networkd RequiredForOnline value.";
      };

      extraRoutes = mkOption {
        type = types.listOf routeModule;
        default = [ ];
        description = "Additional connected routes to install on the interface.";
      };

      ipv6Prefix = mkOption {
        type = types.str;
        default = "::/64";
        description = "Delegated IPv6 prefix slice to advertise on this segment.";
      };

      preferredLifetimeSec = mkOption {
        type = types.int;
        default = 1800;
        description = "Preferred lifetime for advertised IPv6 prefixes.";
      };

      validLifetimeSec = mkOption {
        type = types.int;
        default = 3600;
        description = "Valid lifetime for advertised IPv6 prefixes.";
      };

      privacyExtensions = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the router interface should request temporary IPv6 addresses.";
      };
    };
  };

  mkRoute = route:
    {
      Destination = route.destination;
    }
    // optionalAttrs (route.scope != null) {
      Scope = route.scope;
    };

  mkRoutedInterface = name: iface: {
    matchConfig.Name = iface.device;
    address = [ iface.ipv4Address ];
    routes = map mkRoute iface.extraRoutes;
    linkConfig = optionalAttrs (iface.requiredForOnline != null) {
      RequiredForOnline = iface.requiredForOnline;
    };
    networkConfig =
      {
        DHCPServer = false;
        IPv6SendRA = true;
        DHCPPrefixDelegation = true;
        IPv6PrivacyExtensions = if iface.privacyExtensions then "kernel" else "no";
      }
      // optionalAttrs (iface.dns != [ ]) { DNS = iface.dns; }
      // optionalAttrs (iface.domains != [ ]) { Domains = iface.domains; };
    ipv6SendRAConfig =
      if iface.prefixDelegationMode == "managed" then
        {
          Managed = true;
          OtherInformation = true;
          EmitDNS = iface.dns != [ ];
        }
      else
        {
          Managed = false;
          OtherInformation = false;
          EmitDNS = iface.dns != [ ];
        };
    ipv6Prefixes = [
      {
        Prefix = iface.ipv6Prefix;
        PreferredLifetimeSec = iface.preferredLifetimeSec;
        ValidLifetimeSec = iface.validLifetimeSec;
      }
    ];
  };
in
{
  options.services.router-networking = {
    enable = mkEnableOption "router-focused systemd-networkd configuration";

    useNetworkd = mkOption {
      type = types.bool;
      default = true;
      description = "Enable systemd-networkd and disable generic DHCP management.";
    };

    waitOnline = mkOption {
      type = types.bool;
      default = true;
      description = "Enable systemd-networkd-wait-online.";
    };

    wan = {
      device = mkOption {
        type = types.str;
        description = "WAN interface device name.";
      };

      dhcp = mkOption {
        type = types.str;
        default = "yes";
        description = "systemd-networkd DHCP mode for the WAN interface.";
      };

      ipv6AcceptRA = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to accept IPv6 router advertisements on WAN.";
      };

      dhcpv6Client = mkOption {
        type = types.str;
        default = "always";
        description = "DHCPv6 client mode when using router advertisements.";
      };

      prefixDelegationHint = mkOption {
        type = types.nullOr types.str;
        default = "::/56";
        description = "Optional DHCPv6 prefix delegation hint for the upstream.";
      };

      useAddress = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to request an IPv6 address on the WAN interface.";
      };

      useDNS = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to accept DNS servers from WAN DHCP/RA.";
      };

      privacyExtensions = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the WAN interface should use temporary IPv6 addresses.";
      };
    };

    routedInterfaces = mkOption {
      type = types.attrsOf routedInterfaceModule;
      default = { };
      description = "Routed downstream interfaces that should receive IPv6 prefix delegation and router advertisements.";
    };
  };

  config = mkIf cfg.enable {
    networking.useNetworkd = mkIf cfg.useNetworkd true;
    networking.useDHCP = mkIf cfg.useNetworkd false;
    systemd.network.enable = mkIf cfg.useNetworkd true;
    systemd.network.wait-online.enable = mkIf cfg.waitOnline true;

    systemd.network.networks =
      {
        "10-router-wan" = {
          matchConfig.Name = cfg.wan.device;
          networkConfig = {
            DHCP = cfg.wan.dhcp;
            IPv6AcceptRA = cfg.wan.ipv6AcceptRA;
            IPv6PrivacyExtensions = if cfg.wan.privacyExtensions then "kernel" else "no";
          };
          dhcpV6Config =
            optionalAttrs (cfg.wan.prefixDelegationHint != null) {
              PrefixDelegationHint = cfg.wan.prefixDelegationHint;
            }
            // {
              UseAddress = cfg.wan.useAddress;
            };
          ipv6AcceptRAConfig = {
            DHCPv6Client = cfg.wan.dhcpv6Client;
            UseDNS = cfg.wan.useDNS;
          };
        };
      }
      // mapAttrs' (name: iface: nameValuePair "20-router-${name}" (mkRoutedInterface name iface)) cfg.routedInterfaces;
  };
}
