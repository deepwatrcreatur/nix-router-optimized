{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-nat64;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
in
{
  options.services.router-nat64 = {
    enable = mkEnableOption "NAT64 translation using Tayga";

    ipv6Prefix = mkOption {
      type = types.str;
      default = "64:ff9b::/96";
      description = "The IPv6 prefix used for NAT64 translation (Well-Known Prefix is 64:ff9b::/96).";
    };

    ipv4Pool = mkOption {
      type = types.str;
      default = "192.168.255.0/24";
      description = "The internal IPv4 pool used by Tayga for mapping IPv6 addresses.";
    };

    ipv4RouterAddr = mkOption {
      type = types.str;
      default = "192.168.255.1";
      description = "The IPv4 address of the Tayga interface itself.";
    };

    ipv6RouterAddr = mkOption {
      type = types.str;
      default = "64:ff9b::1";
      description = "The IPv6 address of the Tayga interface itself.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.tayga = {
        enable = true;
        ipv4 = {
          address = cfg.ipv4RouterAddr;
          router.address = cfg.ipv4RouterAddr;
          pool = {
            address = head (splitString "/" cfg.ipv4Pool);
            prefixLength = toInt (last (splitString "/" cfg.ipv4Pool));
          };
        };
        ipv6 = {
          router.address = cfg.ipv6RouterAddr;
          pool = {
            address = head (splitString "/" cfg.ipv6Prefix);
            prefixLength = toInt (last (splitString "/" cfg.ipv6Prefix));
          };
        };
      };

    }

    (if hasRouterFirewall then {
      services.router-firewall.extraForwardRules = mkIf (
        config.services.router-firewall.enable or false
      ) ''
        iifname "nat64" accept comment "Allow NAT64 translated traffic"
      '';
    } else {})
  ]);
}
