{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-networking;
  sanitizeName = name: builtins.replaceStrings [ "." ":" "@" "/" ] [ "-" "-" "-" "-" ] name;

  routeModule = types.submodule {
    options = {
      destination = mkOption {
        type = types.str;
        example = "10.10.0.0/16";
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

      parentDevice = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional parent interface for VLAN-backed routed segments.";
      };

      vlanId = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional VLAN ID. When set, a VLAN netdev is created for this routed segment.";
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
        example = [
          {
            destination = "10.42.0.0/16";
          }
        ];
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

      mtu = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional MTU for the routed interface.";
      };

      policyRouting = {
        enable = mkEnableOption "policy-based routing for this interface";
        table = mkOption {
          type = types.int;
          default = 100;
          description = "Routing table ID for this interface's traffic.";
        };
        rules = mkOption {
          type = types.listOf (types.submodule {
            options = {
              to = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Destination prefix for the rule.";
              };
              table = mkOption {
                type = types.int;
                description = "Routing table to look up.";
              };
              priority = mkOption {
                type = types.int;
                default = 100;
                description = "Rule priority.";
              };
            };
          });
          default = [ ];
          description = "Additional policy routing rules for this interface.";
        };
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

  mkVlanNetdev = item: {
    Kind = "vlan";
    Name = item.child;
    Id = item.vlanId;
  };

  routedVlanDefinitions =
    filter (item: item != null) (
      mapAttrsToList (_name: iface:
        if iface.vlanId != null then
          {
            key = "05-router-vlan-${sanitizeName iface.device}";
            parent = iface.parentDevice;
            child = iface.device;
            vlanId = iface.vlanId;
          }
        else
          null
      ) cfg.routedInterfaces
    );

  wanVlanDefinition =
    if cfg.wan.vlanId != null then
      [
        {
          key = "04-router-vlan-${sanitizeName cfg.wan.device}";
          parent = cfg.wan.parentDevice;
          child = cfg.wan.device;
          vlanId = cfg.wan.vlanId;
        }
      ]
    else
      [ ];

  vlanDefinitions = wanVlanDefinition ++ routedVlanDefinitions;

  parentVlans =
    foldl'
      (acc: item: acc // { ${item.parent} = (acc.${item.parent} or [ ]) ++ [ item.child ]; })
      { }
      vlanDefinitions;

  mkParentVlanNetwork = parent: children: {
    matchConfig.Name = parent;
    networkConfig.VLAN = unique children;
    linkConfig.RequiredForOnline = "no";
  };

  mkWanNetwork = {
    matchConfig.Name = cfg.wan.device;
    address =
      optional
        (cfg.wan.mode == "static" && cfg.wan.ipv4Address != null)
        cfg.wan.ipv4Address;
    routes =
      (optional
        (cfg.wan.mode == "static" && cfg.wan.gateway4 != null)
        {
          Destination = "0.0.0.0/0";
          Gateway = cfg.wan.gateway4;
        })
      ++ map mkRoute cfg.wan.extraRoutes;
    linkConfig =
      optionalAttrs (cfg.wan.requiredForOnline != null) {
        RequiredForOnline = cfg.wan.requiredForOnline;
      }
      // optionalAttrs (cfg.wan.mtu != null) {
        MTUBytes = toString cfg.wan.mtu;
      };
    networkConfig =
      {
        DHCP = if cfg.wan.mode == "dhcp" then cfg.wan.dhcp else "no";
        IPv6AcceptRA = cfg.wan.ipv6AcceptRA;
        IPv6PrivacyExtensions = if cfg.wan.privacyExtensions then "kernel" else "no";
      }
      // optionalAttrs (cfg.wan.mode == "static" && cfg.wan.dns != [ ]) { DNS = cfg.wan.dns; }
      // optionalAttrs (cfg.wan.mode == "static" && cfg.wan.domains != [ ]) { Domains = cfg.wan.domains; };
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

  mkRoutedInterface = name: iface: {
    matchConfig.Name = iface.device;
    address = [ iface.ipv4Address ];
    routes = map mkRoute iface.extraRoutes;
    linkConfig =
      optionalAttrs (iface.requiredForOnline != null) {
        RequiredForOnline = iface.requiredForOnline;
      }
      // optionalAttrs (iface.mtu != null) {
        MTUBytes = toString iface.mtu;
      };
    networkConfig =
      {
        DHCPServer = mkDefault false;
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
    routingPolicyRules =
      (optional iface.policyRouting.enable
        {
          IncomingInterface = iface.device;
          Table = iface.policyRouting.table;
          Priority = 100;
        }
      )
      ++ (map
        (rule: {
          IncomingInterface = iface.device;
          Table = rule.table;
          Priority = rule.priority;
        } // optionalAttrs (rule.to != null) {
          To = rule.to;
        })
        iface.policyRouting.rules);
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
        example = "ens17";
        description = "WAN interface device name.";
      };

      manageWithNetworkd = mkOption {
        type = types.bool;
        default = true;
        description = "Whether systemd-networkd should configure the WAN interface directly.";
      };

      mode = mkOption {
        type = types.enum [ "dhcp" "static" ];
        default = "dhcp";
        description = "Whether the WAN uses DHCP or a static address.";
      };

      parentDevice = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional parent interface for a VLAN-backed WAN.";
      };

      vlanId = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional VLAN ID for the WAN interface.";
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

      ipv4Address = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Static IPv4 CIDR address for the WAN when mode = static.";
      };

      gateway4 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional IPv4 default gateway for a static WAN.";
      };

      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DNS servers to use on a static WAN.";
      };

      domains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Search domains to use on a static WAN.";
      };

      privacyExtensions = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the WAN interface should use temporary IPv6 addresses.";
      };

      requiredForOnline = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional systemd-networkd RequiredForOnline value for the WAN.";
      };

      extraRoutes = mkOption {
        type = types.listOf routeModule;
        default = [ ];
        example = [
          {
            destination = "172.16.0.0/12";
            scope = "link";
          }
        ];
        description = "Additional static routes installed on the WAN interface.";
      };

      mtu = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional MTU for the WAN interface.";
      };
    };

    routedInterfaces = mkOption {
      type = types.attrsOf routedInterfaceModule;
      default = { };
      description = "Routed downstream interfaces that should receive IPv6 prefix delegation and router advertisements.";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      [
        {
          assertion = cfg.wan.vlanId == null || cfg.wan.parentDevice != null;
          message = "router-networking.wan.parentDevice must be set when wan.vlanId is used.";
        }
        {
          assertion =
            cfg.wan.mode != "static"
            || (cfg.wan.ipv4Address != null && cfg.wan.gateway4 != null);
          message = "router-networking.wan.ipv4Address and wan.gateway4 must be set when wan.mode = static.";
        }
      ]
      ++ mapAttrsToList
        (name: iface: {
          assertion = iface.vlanId == null || iface.parentDevice != null;
          message = "router-networking.routedInterfaces.${name}.parentDevice must be set when vlanId is used.";
        })
        cfg.routedInterfaces;

    networking.useNetworkd = mkIf cfg.useNetworkd true;
    networking.useDHCP = mkIf cfg.useNetworkd false;
    systemd.network.enable = mkIf cfg.useNetworkd true;
    systemd.network.wait-online.enable = cfg.waitOnline;

    systemd.network.netdevs =
      listToAttrs (
        map (item: nameValuePair item.key (mkVlanNetdev item)) vlanDefinitions
      );

    systemd.network.networks =
      (optionalAttrs cfg.wan.manageWithNetworkd {
        "10-router-wan" = mkWanNetwork;
      })
      // mapAttrs'
        (parent: children:
          nameValuePair "08-router-parent-${sanitizeName parent}" (mkParentVlanNetwork parent children)
        )
        parentVlans
      // mapAttrs' (name: iface: nameValuePair "20-router-${name}" (mkRoutedInterface name iface)) cfg.routedInterfaces;
  };
}
