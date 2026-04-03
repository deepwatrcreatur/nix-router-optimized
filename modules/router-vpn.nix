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
    networking.wireguard.interfaces = mapAttrs (name: iface: {
      ips = [ iface.ipv4Address ];
      privateKeyFile = iface.privateKeyFile;
      peers = map (peer: {
        publicKey = peer.publicKey;
        allowedIPs = peer.allowedIPs;
      } // optionalAttrs (peer.endpoint != null) {
        endpoint = peer.endpoint;
      } // {
        persistentKeepalive = peer.keepalive;
      }) iface.peers;
      
      # For policy routing, we don't want WireGuard to add routes automatically
      # to the main table. networking.wireguard.interfaces doesn't add them
      # by default unless we specify them in allowedIPs and let it manage it.
      # But we want explicit control.
      
      postSetup = mkIf iface.policyRouting.enable ''
        ${pkgs.iproute2}/bin/ip route add default dev ${iface.device} table ${toString iface.policyRouting.table} || true
      '';
      
      postShutdown = mkIf iface.policyRouting.enable ''
        ${pkgs.iproute2}/bin/ip route del default dev ${iface.device} table ${toString iface.policyRouting.table} || true
      '';
    }) cfg.interfaces;
  };
}
