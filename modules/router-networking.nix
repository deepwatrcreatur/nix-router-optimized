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

  wanModule = types.submodule {
    options = {
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

      metric = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Route metric for this WAN interface. Lower is preferred.";
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

      macAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "00:11:22:33:44:55";
        description = "Optional MAC address to clone on the WAN interface.";
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
    netdevConfig = {
      Kind = "vlan";
      Name = item.child;
    };
    vlanConfig.Id = item.vlanId;
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

  wanVlanDefinitions =
    filter (item: item != null) (
      mapAttrsToList (name: wanCfg:
        if wanCfg.vlanId != null then
          {
            key = "04-router-vlan-${sanitizeName wanCfg.device}";
            parent = wanCfg.parentDevice;
            child = wanCfg.device;
            vlanId = wanCfg.vlanId;
          }
        else
          null
      ) effectiveWans
    );

  vlanDefinitions = wanVlanDefinitions ++ routedVlanDefinitions;

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

  effectiveWans = { primary = cfg.wan; } // cfg.wans;

  mkWanNetwork = name: wanCfg: {
    matchConfig.Name = wanCfg.device;
    address =
      optional
        (wanCfg.mode == "static" && wanCfg.ipv4Address != null)
        wanCfg.ipv4Address;
    routes =
      (optional
        (wanCfg.mode == "static" && wanCfg.gateway4 != null)
        (
          {
            Destination = "0.0.0.0/0";
            Gateway = wanCfg.gateway4;
          }
          // optionalAttrs (wanCfg.metric != null) { Metric = wanCfg.metric; }
        ))
      ++ map mkRoute wanCfg.extraRoutes;
    linkConfig =
      optionalAttrs (wanCfg.requiredForOnline != null) {
        RequiredForOnline = wanCfg.requiredForOnline;
      }
      // optionalAttrs (wanCfg.mtu != null) {
        MTUBytes = toString wanCfg.mtu;
      }
      // optionalAttrs (wanCfg.macAddress != null) {
        MACAddress = wanCfg.macAddress;
      };
    networkConfig =
      {
        DHCP = if wanCfg.mode == "dhcp" then wanCfg.dhcp else "no";
        IPv6AcceptRA = wanCfg.ipv6AcceptRA;
        IPv6PrivacyExtensions = if wanCfg.privacyExtensions then "kernel" else "no";
      }
      // optionalAttrs (wanCfg.mode == "static" && wanCfg.dns != [ ]) { DNS = wanCfg.dns; }
      // optionalAttrs (wanCfg.mode == "static" && wanCfg.domains != [ ]) { Domains = wanCfg.domains; };
    dhcpConfig = mkIf (wanCfg.mode == "dhcp") (
      optionalAttrs (wanCfg.metric != null) {
        RouteMetric = wanCfg.metric;
      }
    );
    dhcpV6Config =
      optionalAttrs (wanCfg.prefixDelegationHint != null) {
        PrefixDelegationHint = wanCfg.prefixDelegationHint;
      }
      // {
        UseAddress = wanCfg.useAddress;
      };
    ipv6AcceptRAConfig = {
      DHCPv6Client = wanCfg.dhcpv6Client;
      UseDNS = wanCfg.useDNS;
    } // optionalAttrs (wanCfg.metric != null) {
      RouteMetric = wanCfg.metric;
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

    wan = mkOption {
      type = wanModule;
      description = "Primary WAN interface configuration.";
    };

    wans = mkOption {
      type = types.attrsOf wanModule;
      default = { };
      description = "Additional WAN interfaces for multi-WAN setups.";
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
      (mapAttrs' (name: wanCfg:
        nameValuePair "10-router-wan-${name}" (mkWanNetwork name wanCfg)
      ) (filterAttrs (_name: wanCfg: wanCfg.manageWithNetworkd) effectiveWans))
      // mapAttrs'
        (parent: children:
          nameValuePair "08-router-parent-${sanitizeName parent}" (mkParentVlanNetwork parent children)
        )
        parentVlans
      // mapAttrs' (name: iface: nameValuePair "20-router-${name}" (mkRoutedInterface name iface)) cfg.routedInterfaces;
  };
}
