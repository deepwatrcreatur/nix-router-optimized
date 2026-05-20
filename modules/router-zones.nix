{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-zones;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  firewallEnabled = hasRouterFirewall && (config.services.router-firewall.enable or false);

  sanitize = name: builtins.replaceStrings [ "." ":" "@" "/" ] [ "-" "-" "-" "-" ] name;

  zoneModule = types.submodule {
    options = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Interfaces assigned to this zone.";
      };

      defaultForwardAction = mkOption {
        type = types.enum [
          "accept"
          "drop"
          "reject"
          "return"
        ];
        default = "return";
        description = ''
          Action taken for forwarded traffic from this zone when no explicit
          zone-to-zone policy matches. The default `return` keeps the base
          `router-firewall` forwarding policy in control.
        '';
      };
    };
  };

  policyModule = types.submodule {
    options = {
      fromZone = mkOption {
        type = types.str;
        description = "Source zone name.";
      };

      toZone = mkOption {
        type = types.str;
        description = "Destination zone name.";
      };

      action = mkOption {
        type = types.enum [
          "accept"
          "drop"
          "reject"
        ];
        default = "accept";
        description = ''
          Forwarding action for traffic from `fromZone` to `toZone`.
        '';
      };
    };
  };

  allInterfaces = concatMap (zone: zone.interfaces) (attrValues cfg.zones);

  renderInterfaceSet =
    interfaces:
    concatStringsSep ", " (map (iface: ''"${iface}"'') interfaces);

  renderPoliciesForZone =
    zoneName:
    concatMapStringsSep "\n" (
      policy:
      let
        destinationZone = cfg.zones.${policy.toZone} or { interfaces = [ ]; };
      in
      optionalString (policy.fromZone == zoneName && destinationZone.interfaces != [ ]) ''
        oifname { ${renderInterfaceSet destinationZone.interfaces} } ${policy.action} comment "router-zones ${policy.fromZone}->${policy.toZone}"
      ''
    ) cfg.policies;
in
{
  options.services.router-zones = {
    enable = mkEnableOption "forward-only zone composition for router-firewall";

    zones = mkOption {
      type = types.attrsOf zoneModule;
      default = { };
      example = {
        lan = {
          interfaces = [ "br-lan" ];
          defaultForwardAction = "return";
        };
        iot = {
          interfaces = [ "br-iot" ];
          defaultForwardAction = "drop";
        };
        wan.interfaces = [ "pppoe-wan" ];
      };
      description = ''
        Forwarding zones keyed by name. Each interface may belong to at most one
        zone.
      '';
    };

    policies = mkOption {
      type = types.listOf policyModule;
      default = [ ];
      example = [
        {
          fromZone = "lan";
          toZone = "wan";
          action = "accept";
        }
        {
          fromZone = "iot";
          toZone = "lan";
          action = "drop";
        }
      ];
      description = ''
        Explicit forwarding policies between source and destination zones.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      assertions =
        [
          {
            assertion = hasRouterFirewall;
            message = "router-zones: import router-firewall before enabling router-zones.";
          }
          {
            assertion = firewallEnabled;
            message = "router-zones: services.router-firewall.enable must be true when router-zones is enabled.";
          }
          {
            assertion = cfg.zones != { };
            message = "router-zones: define at least one zone when enabling the module.";
          }
          {
            assertion = allUnique allInterfaces;
            message = "router-zones: each interface can only belong to one zone.";
          }
          {
            assertion = allUnique (map sanitize (attrNames cfg.zones));
            message = "router-zones: zone names must be unique after sanitization (special characters like . : @ / are replaced with -).";
          }
        ]
        ++ map (policy: {
          assertion = hasAttr policy.fromZone cfg.zones;
          message = "router-zones: policy source zone '${policy.fromZone}' does not exist.";
        }) cfg.policies
        ++ map (policy: {
          assertion = hasAttr policy.toZone cfg.zones;
          message = "router-zones: policy destination zone '${policy.toZone}' does not exist.";
        }) cfg.policies;
    })

    (if hasRouterFirewall then
      mkIf (cfg.enable && firewallEnabled) {
        services.router-firewall.extraFilterTableRules = mkAfter ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: zone:
              let
                chainName = "zone_${sanitize name}_forward";
                policyRules = renderPoliciesForZone name;
              in
              ''
                chain ${chainName} {
                  ${optionalString (policyRules != "") policyRules}
                  ${zone.defaultForwardAction} comment "router-zones default for ${name}"
                }
              ''
            ) cfg.zones
          )}
        '';

        services.router-firewall.extraForwardEarlyRules = mkBefore ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              name: zone:
              optionalString (zone.interfaces != [ ]) ''
                iifname { ${renderInterfaceSet zone.interfaces} } jump zone_${sanitize name}_forward
              ''
            ) cfg.zones
          )}
        '';
      }
    else
      { })
  ];
}
