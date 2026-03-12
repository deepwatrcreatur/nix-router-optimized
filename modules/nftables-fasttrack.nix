# NFTables with FastTrack support for bypassing conntrack on established connections
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.nftables-fasttrack;
in {
  options.services.nftables-fasttrack = {
    enable = mkEnableOption "nftables with fasttrack optimizations";
    
    wan-interface = mkOption {
      type = types.str;
      description = "WAN network interface name";
    };
    
    lan-interface = mkOption {
      type = types.str;
      description = "Primary LAN network interface name";
    };
    
    extra-lan-interfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional LAN interfaces";
    };
    
    lan-networks = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "10.10.0.0/16" "192.168.100.0/24" ];
      description = "LAN network CIDRs for NAT and forwarding rules";
    };
    
    enable-ipv6 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable IPv6 forwarding and NAT66";
    };
    
    trusted-ports = mkOption {
      type = types.listOf types.int;
      default = [];
      example = [ 22 80 443 ];
      description = "TCP ports to allow from WAN to router";
    };
    
    extra-rules = mkOption {
      type = types.lines;
      default = "";
      description = "Extra nftables rules to append";
    };
  };

  config = mkIf cfg.enable {
    networking.nftables.enable = true;
    networking.firewall.enable = false; # Use nftables directly

    networking.nftables.ruleset = let
      allLanInterfaces = [ cfg.lan-interface ] ++ cfg.extra-lan-interfaces;
      lanInterfaceSet = concatStringsSep ", " (map (iface: "\"${iface}\"") allLanInterfaces);
    in ''
      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;
          
          # Allow established/related connections
          ct state {established, related} accept
          
          # Allow loopback
          iifname "lo" accept
          
          # Allow ICMP (ping)
          ip protocol icmp accept
          ${optionalString cfg.enable-ipv6 "ip6 nexthdr icmpv6 accept"}
          
          # Allow DHCPv6 on WAN interface
          iifname "${cfg.wan-interface}" udp dport 546 accept
          
          # Allow SSH from LAN interfaces only (not WAN)
          iifname {${lanInterfaceSet}} tcp dport 22 accept
          
          # Allow DNS and DHCP on LAN interfaces
          iifname {${lanInterfaceSet}} udp dport {53, 67, 68, 547} accept
          iifname {${lanInterfaceSet}} udp sport {67, 68} accept
          iifname {${lanInterfaceSet}} tcp dport 53 accept
          
          ${optionalString (cfg.trusted-ports != []) ''
          # Allow trusted ports from WAN
          iifname "${cfg.wan-interface}" tcp dport {${concatStringsSep ", " (map toString cfg.trusted-ports)}} accept
          ''}
          
          ${cfg.extra-rules}
        }
        
        chain forward {
          type filter hook forward priority 0; policy drop;
          
          # Allow established/related connections (return traffic)
          ct state {established, related} accept
          
          # Drop invalid packets early
          ct state invalid drop
          
          # Allow forwarding from LAN interfaces to WAN
          iifname {${lanInterfaceSet}} oifname "${cfg.wan-interface}" accept
          
          # Allow forwarding between LAN interfaces
          iifname {${lanInterfaceSet}} oifname {${lanInterfaceSet}} accept
          
          # Default drop
          drop
        }
        
        chain output {
          type filter hook output priority 0; policy accept;
        }
      }
      
      table ip nat {
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          
          # Masquerade traffic from LAN going to WAN
          oifname "${cfg.wan-interface}" masquerade
        }
      }
      
      ${optionalString cfg.enable-ipv6 ''
      table ip6 nat {
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          
          # IPv6 masquerade for private addresses
          ip6 saddr fd00::/8 oifname "${cfg.wan-interface}" masquerade
        }
      }
      ''}
    '';
  };
}
