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

    (optionalAttrs hasRouterFirewall (mkIf routerFirewallEnabled (
      let
        fwCfg = config.services.router-firewall;
        optimizationInterfaces = config.services.router-optimizations.interfaces or { };
        interfaceByRole = role:
          mapAttrsToList (_name: iface: iface.device) (
            filterAttrs (_name: iface: iface.role == role) optimizationInterfaces
          );
        wanInterfaces = if fwCfg.wanInterfaces != [ ] then fwCfg.wanInterfaces else interfaceByRole "wan";
        lanInterfaces = if fwCfg.lanInterfaces != [ ] then fwCfg.lanInterfaces else interfaceByRole "lan";
        managementInterfaces = if fwCfg.managementInterfaces != [ ] then fwCfg.managementInterfaces else interfaceByRole "management";
        trustedInterfaces = unique (fwCfg.extraTrustedInterfaces ++ lanInterfaces ++ managementInterfaces);
        quotedSet = ifaces: concatStringsSep ", " (map (iface: "\"${iface}\"") ifaces);
        maybeSet = ifaces: if ifaces == [ ] then "" else "{${quotedSet ifaces}}";
        natIface = translationBackend.firewall.forwardInputInterface;
      in
      {
        services.router-firewall.extraInputRules = ''
          iifname "${natIface}" accept comment "Allow NAT64 translated traffic"
        '';

        services.router-firewall.extraForwardRules = ''
          ${optionalString (trustedInterfaces != [ ]) ''iifname ${maybeSet trustedInterfaces} oifname "${natIface}" accept comment "NAT64: forward to translation"''}
          ${optionalString (wanInterfaces != [ ]) ''iifname "${natIface}" oifname ${maybeSet wanInterfaces} accept comment "NAT64: forward from translation"''}
        '';
      }
    )))
  ]);
}
