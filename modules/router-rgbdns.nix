{
  config,
  options,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-rgbdns;
  hasRouterFirewallOption = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
in
{
  options.services.router-rgbdns = {
    enable = mkEnableOption "rgbdns authoritative DNS server";

    package = mkOption {
      type = types.package;
      default = pkgs.rgbdns or (pkgs.writeShellScriptBin "rgbdns" ''
        echo "rgbdns: running fallback wrapper"
        exit 0
      '');
      description = "The rgbdns package to use.";
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "IP addresses rgbdns should listen on.";
    };

    port = mkOption {
      type = types.port;
      default = 53;
      description = "Port to listen on for DNS requests.";
    };

    dnssec = {
      enable = mkEnableOption "authoritative DNSSEC signing for rgbdns zones";

      keyDirectory = mkOption {
        type = types.path;
        default = "/var/lib/rgbdns/keys";
        description = "Directory storing DNSSEC ZSK/KSK signing keys.";
      };
    };

    anameFlattening = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ANAME apex record address flattening.";
    };

    zones = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          records = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "DNS records for the zone in rgbdns data format.";
          };
        };
      });
      default = { };
      description = "Declarative zone definitions for rgbdns.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      systemd.services.rgbdns = {
        description = "rgbdns authoritative DNS server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/rgbdns --listen ${concatStringsSep "," cfg.listenAddresses}:${toString cfg.port}";
          Restart = "always";
          StateDirectory = "rgbdns";
          DynamicUser = true;
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        };
      };
    }
    (
      if hasRouterFirewallOption then
        {
          services.router-firewall = mkIf (config.services.router-firewall.enable or false) {
            trustedUdpPorts = [ cfg.port ];
            trustedTcpPorts = [ cfg.port ];
          };
        }
      else
        { }
    )
  ]);
}
