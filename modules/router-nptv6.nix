{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-nptv6;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;

  staticRules = filter (r: !r.autoDetect) cfg.rules;
  dynamicRules = filter (r: r.autoDetect) cfg.rules;

  # Fallback to stateful SNAT/DNAT for prefix translation
  # This avoids the 'npt' keyword which is failing 'No symbol type information' in some environments
  mkNptv6PostroutingRule = rule: ''
    # Stateful SNAT for ${rule.internalPrefix} -> ${rule.externalPrefix} on ${rule.externalInterface}
    ip6 saddr ${rule.internalPrefix} oifname "${rule.externalInterface}" snat to ${rule.externalPrefix}
  '';

  mkNptv6PreroutingRule = rule: ''
    # Stateful DNAT for ${rule.externalPrefix} -> ${rule.internalPrefix} on ${rule.externalInterface}
    ip6 daddr ${rule.externalPrefix} iifname "${rule.externalInterface}" dnat to ${rule.internalPrefix}
  '';

  staticRuleset = ''
    table ip6 nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ${concatMapStrings mkNptv6PostroutingRule staticRules}
      }
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        ${concatMapStrings mkNptv6PreroutingRule staticRules}
      }
    }
  '';

  # Watcher script for dynamic prefixes
  watchScript = pkgs.writeShellScriptBin "router-nptv6-watch" ''
    set -euo pipefail

    # Arrays are passed from Environment variable strings
    IFS=' ' read -r -a INTERNAL_PREFIXES <<< "$VAGLIO_NPT_INTERNAL_PREFIXES"
    IFS=' ' read -r -a EXTERNAL_INTERFACES <<< "$VAGLIO_NPT_EXTERNAL_INTERFACES"

    setup_table() {
      ${pkgs.nftables}/bin/nft "add table ip6 router-npt-dynamic" || true
      ${pkgs.nftables}/bin/nft "add chain ip6 router-npt-dynamic postrouting { type nat hook postrouting priority 110; policy accept; }" || true
      ${pkgs.nftables}/bin/nft "add chain ip6 router-npt-dynamic prerouting { type nat hook prerouting priority -110; policy accept; }" || true
    }

    update_rules() {
      echo "Checking for prefix changes..."
      NEW_RULES=""
      for i in "''${!EXTERNAL_INTERFACES[@]}"; do
        IFACE="''${EXTERNAL_INTERFACES[$i]}"
        INT_PREFIX="''${INTERNAL_PREFIXES[$i]}"
        
        # Get first GUA /64 prefix
        EXT_PREFIX=$(${pkgs.iproute2}/bin/ip -6 addr show dev "$IFACE" scope global | \
          ${pkgs.gnugrep}/bin/grep -oP '(?<=inet6 )[0-9a-f:]+(?=/64)' | \
          ${pkgs.coreutils}/bin/head -n 1 || true)
          
        if [[ -n "$EXT_PREFIX" ]]; then
          EXT_PREFIX="''${EXT_PREFIX}/64"
          echo "Found prefix $EXT_PREFIX for $IFACE"
          NEW_RULES+="add rule ip6 router-npt-dynamic postrouting ip6 saddr $INT_PREFIX oifname \"$IFACE\" snat to $EXT_PREFIX
"
          NEW_RULES+="add rule ip6 router-npt-dynamic prerouting ip6 daddr $EXT_PREFIX iifname \"$IFACE\" dnat to $INT_PREFIX
"
        else
          echo "No prefix found for $IFACE"
        fi
      done

      # Atomically update the dynamic table
      {
        echo "flush table ip6 router-npt-dynamic"
        if [[ -n "$NEW_RULES" ]]; then
          echo "$NEW_RULES"
        fi
      } | ${pkgs.nftables}/bin/nft -f -
    }

    setup_table
    update_rules

    # Monitor for address changes
    ${pkgs.iproute2}/bin/ip -6 monitor address | while read -r line; do
      # Trigger update on any IPv6 address event
      update_rules
    done
  '';
in
{
  options.services.router-nptv6 = {
    enable = mkEnableOption "NPTv6 (Network Prefix Translation) for IPv6 (Stateful Fallback)";

    rules = mkOption {
      type = types.listOf (types.submodule {
        options = {
          internalPrefix = mkOption {
            type = types.str;
            example = "fd00:1::/64";
            description = "The internal (stable) IPv6 prefix to be translated.";
          };
          externalInterface = mkOption {
            type = types.str;
            example = "tailscale0";
            description = "The external interface where the translation should occur.";
          };
          externalPrefix = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "2001:db8:1::/64";
            description = "The external (dynamic) IPv6 prefix to translate to. Optional if autoDetect is enabled.";
          };
          autoDetect = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to automatically detect the external prefix on the specified interface.";
          };
        };
      });
      default = [ ];
      description = "List of NPTv6 translation rules.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = all (r: r.autoDetect || r.externalPrefix != null) cfg.rules;
          message = "services.router-nptv6.rules: externalPrefix must be specified if autoDetect is disabled.";
        }
      ];

      networking.nftables.enable = true;
      networking.nftables.ruleset = mkIf (!config.services.router-firewall.enable or false) staticRuleset;

      systemd.services.router-nptv6-watch = mkIf (dynamicRules != [ ]) {
        description = "Dynamic NPTv6 Prefix Watcher";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${watchScript}/bin/router-nptv6-watch";
          Restart = "always";
          RestartSec = "5s";
          Environment = [
            "VAGLIO_NPT_INTERNAL_PREFIXES=${concatMapStringsSep " " (r: r.internalPrefix) dynamicRules}"
            "VAGLIO_NPT_EXTERNAL_INTERFACES=${concatMapStringsSep " " (r: r.externalInterface) dynamicRules}"
          ];
        };
      };
    }

    # Integration with router-firewall
    (if hasRouterFirewall then {
      services.router-firewall.extraIpv6NatRules = mkIf (config.services.router-firewall.enable or false) (
        concatMapStrings mkNptv6PostroutingRule staticRules
      );

      services.router-firewall.extraIpv6PreroutingRules = mkIf (config.services.router-firewall.enable or false) (
        concatMapStrings mkNptv6PreroutingRule staticRules
      );
    } else { })
  ]);
}
