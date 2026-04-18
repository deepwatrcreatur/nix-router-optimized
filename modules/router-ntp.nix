{
  config,
  options,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.router-ntp;
  hasRouterFirewallOption = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
in
{
  options.services.router-ntp = {
    enable = mkEnableOption "chrony NTP server for router LAN clients";

    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [
        "time.cloudflare.com"
        "time.google.com"
        "0.nixos.pool.ntp.org"
        "1.nixos.pool.ntp.org"
      ];
      description = "Upstream NTP servers to synchronise from.";
    };

    lanSubnets = mkOption {
      type = types.listOf types.str;
      default = [ "10.0.0.0/8" ];
      description = "Subnets to allow NTP queries from (chrony `allow` directives).";
    };

    localStratum = mkOption {
      type = types.int;
      default = 10;
      description = "Stratum to advertise when serving time without upstream sync.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # chrony handles both upstream sync and serving to LAN clients.
      # systemd-timesyncd is client-only and must be disabled to avoid port
      # conflicts on UDP 123.
      services.timesyncd.enable = false;

      services.chrony = {
        enable = true;
        servers = cfg.upstreamServers;
        extraConfig = concatStringsSep "\n" (
          (map (subnet: "allow ${subnet}") cfg.lanSubnets)
          ++ [ "local stratum ${toString cfg.localStratum}" ]
        );
      };
    }

    (
      if hasRouterFirewallOption then
        {
          # Open UDP 123 on trusted (LAN) interfaces so clients can reach chrony.
          services.router-firewall = mkIf (config.services.router-firewall.enable or false) {
            trustedUdpPorts = [ 123 ];
          };
        }
      else
        { }
    )
  ]);
}
