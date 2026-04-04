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
    systemd.network.netdevs = mapAttrs' (name: iface: nameValuePair "30-${iface.device}" {
      netdevConfig = {
        Name = iface.device;
        Kind = "wireguard";
      };
      wireguardConfig = {
        PrivateKeyFile = iface.privateKeyFile;
      };
      wireguardPeers = map (peer: {
        PublicKey = peer.publicKey;
        AllowedIPs = peer.allowedIPs;
        Endpoint = peer.endpoint;
        PersistentKeepalive = peer.keepalive;
      }) iface.peers;
    }) cfg.interfaces;

    systemd.network.networks = mapAttrs' (name: iface: nameValuePair "30-${iface.device}" {
      matchConfig.Name = iface.device;
      address = [ iface.ipv4Address ];
      
      # If policy routing is enabled, add the default route to the specified table
      routes = mkIf iface.policyRouting.enable [
        {
          Destination = "0.0.0.0/0";
          Table = iface.policyRouting.table;
        }
      ];
      
      # We usually don't want to manage this interface via DHCP
      networkConfig = {
        IPv4Forwarding = "yes";
        IPv6Forwarding = "yes";
      };
    }) cfg.interfaces;
  };
}
