{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-nat64;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  translationBackendLib = import ./router-translation-backend-lib.nix { inherit lib; };
  translationBackend = translationBackendLib.mkTaygaAdapter {
    interfaceName = "nat64";
    inherit (cfg)
      ipv4Pool
      ipv6Prefix
      ipv4RouterAddr
      ipv6RouterAddr
      ;
    stateDirectory = "/var/lib/tayga";
    serviceUnit = "tayga.service";
  };
in
{
  options.services.router-nat64 = {
    enable = mkEnableOption "the current Tayga-backed NAT64 translation path";

    ipv6Prefix = mkOption {
      type = types.str;
      default = "64:ff9b::/96";
      description = "The IPv6 prefix used for NAT64 translation (Well-Known Prefix is 64:ff9b::/96).";
    };

    ipv4Pool = mkOption {
      type = types.str;
      default = "192.168.255.0/24";
      description = "The internal IPv4 pool used by the current NAT64 backend for IPv6-to-IPv4 mapping.";
    };

    ipv4RouterAddr = mkOption {
      type = types.str;
      default = "192.168.255.1";
      description = "The IPv4 address of the current Tayga-backed translation interface.";
    };

    ipv6RouterAddr = mkOption {
      type = types.str;
      default = "64:ff9b::1";
      description = "The IPv6 address of the current Tayga-backed translation interface.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.tayga = translationBackend.tayga.serviceAttrs;
    }

    (if hasRouterFirewall then {
      services.router-firewall.extraForwardRules = mkIf (
        config.services.router-firewall.enable or false
      ) ''
        iifname "${translationBackend.firewall.forwardInputInterface}" accept comment "Allow NAT64 translated traffic"
      '';
    } else {})
  ]);
}
