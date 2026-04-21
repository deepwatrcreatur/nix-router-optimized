{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-bgp;
in
{
  options.services.router-bgp = {
    enable = mkEnableOption "Simplified BGP routing via FRR";

    asn = mkOption {
      type = types.ints.unsigned;
      example = 65001;
      description = "Local Autonomous System Number (ASN).";
    };

    routerId = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.10.10.1";
      description = "BGP Router ID (usually the primary LAN IP).";
    };

    neighbors = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          remoteAs = mkOption {
            type = types.ints.unsigned;
            description = "Remote ASN.";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Description for the neighbor.";
          };
          nextHopSelf = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to set next-hop-self for this neighbor.";
          };
        };
      });
      default = { };
      example = {
        "10.10.11.50" = {
          remoteAs = 65002;
          description = "Proxmox Node 1";
        };
      };
      description = "BGP neighbors to peer with.";
    };

    networks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.0.0/16" ];
      description = "Network prefixes to advertise via BGP.";
    };
  };

  config = mkIf cfg.enable {
    services.frr = {
      bgpd.enable = true;
      config = ''
        router bgp ${toString cfg.asn}
          ${optionalString (cfg.routerId != null) "bgp router-id ${cfg.routerId}"}
          ${concatStringsSep "\n" (mapAttrsToList (ip: neighbor: ''
            neighbor ${ip} remote-as ${toString neighbor.remoteAs}
            ${optionalString (neighbor.description != "") "neighbor ${ip} description ${neighbor.description}"}
            ${optionalString neighbor.nextHopSelf "neighbor ${ip} next-hop-self"}
          '') cfg.neighbors)}
          ${concatStringsSep "\n" (map (network: "network ${network}") cfg.networks)}
        !
      '';
    };

    # Open BGP port in firewall
    networking.firewall.allowedTCPPorts = [ 179 ];
  };
}
