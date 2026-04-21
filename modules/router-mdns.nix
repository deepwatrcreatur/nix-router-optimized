{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-mdns;
in
{
  options.services.router-mdns = {
    enable = mkEnableOption "mDNS reflection across VLANs using Avahi";

    allowInterfaces = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [ "enp6s16" "enp6s18" ];
      description = ''
        List of network interfaces that should participate in mDNS reflection.
        If null, all local interfaces (except loopback and point-to-point) will be used.
      '';
    };

    ipv4 = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to use IPv4 for mDNS.";
    };

    ipv6 = mkOption {
      type = types.bool;
      default = config.networking.enableIPv6;
      defaultText = literalExpression "config.networking.enableIPv6";
      description = "Whether to use IPv6 for mDNS.";
    };
  };

  config = mkIf cfg.enable {
    services.avahi = {
      enable = true;
      reflector = true;
      ipv4 = cfg.ipv4;
      ipv6 = cfg.ipv6;
      allowInterfaces = cfg.allowInterfaces;
      # openFirewall is true by default in the avahi module
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}
