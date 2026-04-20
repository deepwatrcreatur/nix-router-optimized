{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-dns64;
  nat64Cfg = config.services.router-nat64;
  dnsCfg = config.router.dns;
in
{
  options.services.router-dns64 = {
    enable = mkEnableOption "DNS64 synthesis in Unbound";

    prefix = mkOption {
      type = types.str;
      default = if nat64Cfg.enable then nat64Cfg.ipv6Prefix else "64:ff9b::/96";
      defaultText = "services.router-nat64.ipv6Prefix or 64:ff9b::/96";
      description = "The IPv6 prefix used for DNS64 synthesis.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = dnsCfg.enable && dnsCfg.provider == "unbound";
        message = "router-dns64 requires services.router-dns-service.provider = \"unbound\".";
      }
    ];

    services.unbound.settings.server = {
      module-config = mkBefore "\"dns64 validator iterator\"";
      dns64-prefix = head (splitString "/" cfg.prefix);
    };
  };
}
