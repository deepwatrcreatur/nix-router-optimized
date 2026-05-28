{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-nat64;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  routerFirewallEnabled = hasRouterFirewall && attrByPath [ "services" "router-firewall" "enable" ] false config;
  translationBackendLib = import ./router-translation-backend-lib.nix { inherit lib; };
  hasJoolCli = builtins.hasAttr "jool-cli" pkgs;
  joolUnsupportedMessage =
    if hasJoolCli then
      "router-nat64: translationBackend.backend = jool-experimental is only a bounded spike today. nixpkgs exposes jool-cli, but this repo does not yet have a supported Jool runtime/kernel-module lifecycle for NAT64."
    else
      "router-nat64: translationBackend.backend = jool-experimental is unavailable here because nixpkgs does not expose the required Jool runtime packaging.";
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

    translationBackend = {
      backend = mkOption {
        type = types.enum [ "tayga" "jool-experimental" ];
        default = "tayga";
        description = "Current NAT64 backend selection. Jool remains experimental and unsupported beyond bounded spike evaluation.";
      };

      allowExperimentalJool = mkOption {
        type = types.bool;
        default = false;
        description = "Require explicit acknowledgement before selecting the bounded Jool evaluation path.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.translationBackend.backend != "jool-experimental" || cfg.translationBackend.allowExperimentalJool;
          message = "router-nat64: translationBackend.backend = jool-experimental requires translationBackend.allowExperimentalJool = true so experimental backend selection cannot happen silently.";
        }
        {
          assertion = cfg.translationBackend.backend != "jool-experimental";
          message = joolUnsupportedMessage;
        }
      ];

      services.tayga = translationBackend.tayga.serviceAttrs;
    }

    (optionalAttrs hasRouterFirewall (mkIf routerFirewallEnabled {
      services.router-firewall.extraInputRules = ''
        iifname "${translationBackend.firewall.forwardInputInterface}" accept comment "Allow NAT64 translated traffic"
      '';

      services.router-firewall.extraForwardRules = ''
        oifname "${translationBackend.firewall.forwardInputInterface}" accept comment "NAT64: forward to translation"
        iifname "${translationBackend.firewall.forwardInputInterface}" accept comment "NAT64: forward from translation"
      '';
    }))
  ]);
}
