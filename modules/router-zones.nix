{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-zones;
  firewallCfg = config.services.router-firewall;

  zoneModule = types.submodule {
    options = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of interface names belonging to this zone.";
      };

      defaultInputPolicy = mkOption {
        type = types.enum [
          "accept"
          "drop"
          "reject"
        ];
        default = "drop";
        description = "Default policy for traffic destined for the router itself from this zone.";
      };

      defaultForwardPolicy = mkOption {
        type = types.enum [
          "accept"
          "drop"
          "reject"
        ];
        default = "drop";
        description = "Default policy for traffic originating from this zone destined for other zones.";
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
        description = "Action to take for traffic between these zones.";
      };
      extraRules = mkOption {
        type = types.lines;
        default = "";
        description = "Extra nftables rules for this specific zone pair (e.g., port restrictions).";
      };
    };
  };

  # Helper to get all interfaces across all zones
  allZoneInterfaces = unique (concatLists (mapAttrsToList (name: zone: zone.interfaces) cfg.zones));

  # Sanitize name for nftables
  sanitize = name: builtins.replaceStrings [ "." ":" "@" "/" ] [ "-" "-" "-" "-" ] name;

in
{
  options.services.router-zones = {
    enable = mkEnableOption "Zone-based firewall policy management";

    zones = mkOption {
      type = types.attrsOf zoneModule;
      default = { };
      example = {
        wan = {
          interfaces = [ "enp6s17" ];
          defaultForwardPolicy = "drop";
        };
        lan = {
          interfaces = [ "enp6s16" ];
          defaultForwardPolicy = "accept";
        };
        iot = {
          interfaces = [ "enp6s16.20" ];
          defaultForwardPolicy = "drop";
        };
      };
      description = "Definition of security zones.";
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
          toZone = "wan";
          action = "accept";
        }
        {
          fromZone = "iot";
          toZone = "lan";
          action = "drop";
          extraRules = "ip daddr 10.10.10.50 tcp dport 8123 accept comment \"Allow IoT to Home Assistant\"";
        }
      ];
      description = "Explicit traffic policies between zones.";
    };
  };

  config = mkIf cfg.enable {
    services.router-firewall.extraFilterTableRules = ''
      # Zone chains
      ${concatStringsSep "\n" (
        mapAttrsToList (name: zone: ''
          chain zone_${sanitize name}_in {
            ${optionalString (zone.interfaces != [ ])
              "iifname { ${
                concatStringsSep ", " (map (i: ''"${i}"'') zone.interfaces)
              } } jump zone_${sanitize name}_policy"
            }
          }
        '') cfg.zones
      )}

      # Policy enforcement chains
      ${concatStringsSep "\n" (
        mapAttrsToList (name: zone: ''
          chain zone_${sanitize name}_policy {
            # Established/Related is handled by main firewall, but we can add zone-specific ones here

            # Explicit Policies
            ${concatMapStringsSep "\n" (p: ''
              ${optionalString (p.fromZone == name) (
                let
                  toZoneCfg = cfg.zones.${p.toZone};
                in
                ''
                  ${optionalString (toZoneCfg.interfaces != [ ]) ''
                    oifname { ${concatStringsSep ", " (map (i: ''"${i}"'') toZoneCfg.interfaces)} } ${p.extraRules}
                    oifname { ${
                      concatStringsSep ", " (map (i: ''"${i}"'') toZoneCfg.interfaces)
                    } } ${p.action} comment "Policy: ${p.fromZone} -> ${p.toZone}"
                  ''}
                ''
              )}
            '') cfg.policies}

            # Default Zone Forward Policy
            ${zone.defaultForwardPolicy} comment "Default Forward Policy for zone ${name}"
          }
        '') cfg.zones
      )}
    '';

    # Integrate with the main forward hook
    services.router-firewall.extraForwardRules = mkBefore ''
      # Dispatch to zone-based policy chains
      ${concatStringsSep "\n" (
        mapAttrsToList (name: zone: ''
          ${optionalString (zone.interfaces != [ ])
            "iifname { ${
              concatStringsSep ", " (map (i: ''"${i}"'') zone.interfaces)
            } } jump zone_${sanitize name}_policy"
          }
        '') cfg.zones
      )}
    '';
  };
}
