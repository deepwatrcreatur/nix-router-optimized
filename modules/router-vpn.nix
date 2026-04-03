{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-vpn;
  
  vpnInterfaceModule = types.submodule {
    options = {
      device = mkOption {
        type = types.str;
        description = "Name of the VPN interface (e.g., wg0).";
      };

      ipv4Address = mkOption {
        type = types.str;
        description = "IPv4 address for the VPN interface (CIDR format).";
      };

      privateKeyFile = mkOption {
        type = types.str;
        description = "Path to the private key file.";
      };

      peers = mkOption {
        type = types.listOf (types.submodule {
          options = {
            publicKey = mkOption { type = types.str; };
            allowedIPs = mkOption { type = types.listOf types.str; default = [ "0.0.0.0/0" ]; };
            endpoint = mkOption { type = types.nullOr types.str; default = null; };
            keepalive = mkOption { type = types.int; default = 25; };
          };
        });
        default = [ ];
      };

      policyRouting = {
        enable = mkEnableOption "policy-based routing for this VPN";
        table = mkOption {
          type = types.int;
          default = 100;
          description = "Routing table ID for this VPN's default route.";
        };
      };
    };
  };
in
{
  options.services.router-vpn = {
    enable = mkEnableOption "VPN support for routers";
    
    interfaces = mkOption {
      type = types.attrsOf vpnInterfaceModule;
      default = { };
      description = "VPN interface definitions.";
    };
  };

  config = mkIf cfg.enable {
    networking.wg-quick.interfaces = mapAttrs (name: iface: {
      address = [ iface.ipv4Address ];
      privateKeyFile = iface.privateKeyFile;
      
      # Table = "off" prevents wg-quick from adding routes to the main table,
      # which is necessary for policy routing.
      extraConfig = mkIf iface.policyRouting.enable ''
        [Interface]
        Table = off
      '';

      peers = map (peer: {
        publicKey = peer.publicKey;
        allowedIPs = peer.allowedIPs;
      } // optionalAttrs (peer.endpoint != null) {
        endpoint = peer.endpoint;
      } // {
        persistentKeepalive = peer.keepalive;
      }) iface.peers;
      
      # If policy routing is enabled, we use postUp to add the default route
      # to the specific table instead of the main table.
      postUp = mkIf iface.policyRouting.enable ''
        ${pkgs.iproute2}/bin/ip route add default dev ${iface.device} table ${toString iface.policyRouting.table}
      '';
      
      # Do not let wg-quick add routes to the main table if we want policy routing
      autostart = true;
    }) cfg.interfaces;
  };
}
