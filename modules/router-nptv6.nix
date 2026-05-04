{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-nptv6;

  mkNptv6PostroutingRule = rule: ''
    # Rule for ${rule.internalPrefix} -> ${rule.externalPrefix} on ${rule.externalInterface} (POSTROUTING)
    ip6 saddr ${rule.internalPrefix} oifname "${rule.externalInterface}" snat to ${rule.externalPrefix} npt
  '';

  mkNptv6PreroutingRule = rule: ''
    # Rule for ${rule.externalPrefix} -> ${rule.internalPrefix} on ${rule.externalInterface} (PREROUTING)
    ip6 daddr ${rule.externalPrefix} iifname "${rule.externalInterface}" dnat to ${rule.internalPrefix} npt
  '';

  ruleset = ''
    table ip6 nat {
      chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ${concatMapStrings mkNptv6PostroutingRule cfg.rules}
      }
      chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        ${concatMapStrings mkNptv6PreroutingRule cfg.rules}
      }
    }
  '';
in
{
  options.services.router-nptv6 = {
    enable = mkEnableOption "NPTv6 (Network Prefix Translation) for IPv6";

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
            type = types.str;
            example = "2001:db8:1::/64";
            description = "The external (dynamic) IPv6 prefix to translate to.";
          };
        };
      });
      default = [ ];
      description = "List of NPTv6 translation rules.";
    };
  };

  config = mkIf cfg.enable {
    networking.nftables.enable = true;
    networking.nftables.ruleset = mkIf (!config.services.router-firewall.enable or false) ruleset;

    # Integration with router-firewall
    services.router-firewall.extraIpv6NatRules = mkIf (config.services.router-firewall.enable or false) (
      concatMapStrings mkNptv6PostroutingRule cfg.rules
    );

    services.router-firewall.extraIpv6PreroutingRules = mkIf (config.services.router-firewall.enable or false) (
      concatMapStrings mkNptv6PreroutingRule cfg.rules
    );
  };
}
