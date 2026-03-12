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
      lanNetworkSet = concatStringsSep ", " cfg.lan-networks;
      trustedPortSet = concatStringsSep ", " (map toString cfg.trusted-ports);
    in ''
      # Flush existing rules
      flush ruleset

      # Define interface and network sets
      define WAN = ${cfg.wan-interface}
      define LAN = { ${lanInterfaceSet} }
      define LAN_NETS = { ${lanNetworkSet} }

      # IPv4 Tables
      table inet filter {
        # Flowtable for hardware/software flow offloading (FastTrack equivalent)
        flowtable f {
          hook ingress priority 0;
          devices = { $WAN, $LAN };
        }

        chain input {
          type filter hook input priority 0; policy drop;

          # Allow established/related connections (stateful)
          ct state established,related accept

          # Allow loopback
          iif lo accept

          # Allow ICMPv4
          ip protocol icmp accept
          
          ${optionalString cfg.enable-ipv6 ''
          # Allow ICMPv6
          ip6 nexthdr icmpv6 accept
          ''}

          # Allow SSH, DNS, and other services from LAN
          iifname $LAN tcp dport { 22, 53 } accept
          iifname $LAN udp dport { 53, 67 } accept

          ${optionalString (cfg.trusted-ports != []) ''
          # Allow trusted ports from WAN
          iifname $WAN tcp dport { ${trustedPortSet} } accept
          ''}

          # Drop invalid packets
          ct state invalid drop

          # Log and drop everything else
          log prefix "INPUT DROP: " limit rate 5/minute
          drop
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          # Offload established connections to flowtable (FastTrack)
          ip protocol { tcp, udp } flow add @f

          # Allow established/related connections
          ct state established,related accept

          # Allow LAN to WAN
          iifname $LAN oifname $WAN accept

          ${optionalString cfg.enable-ipv6 ''
          # Allow IPv6 forwarding
          ip6 saddr fd00::/8 oifname $WAN accept
          ''}

          # Drop invalid packets
          ct state invalid drop

          # Log and drop everything else
          log prefix "FORWARD DROP: " limit rate 5/minute
          drop
        }

        chain output {
          type filter hook output priority 0; policy accept;
        }
      }

      # NAT table
      table inet nat {
        chain prerouting {
          type nat hook prerouting priority -100; policy accept;
          # Port forwarding rules can be added here
        }

        chain postrouting {
          type nat hook postrouting priority 100; policy accept;

          # Masquerade LAN to WAN (IPv4 NAT)
          ip saddr $LAN_NETS oifname $WAN masquerade

          ${optionalString cfg.enable-ipv6 ''
          # IPv6 NAT (NAT66) if needed
          ip6 saddr fd00::/8 oifname $WAN masquerade
          ''}
        }
      }

      ${cfg.extra-rules}
    '';
  };
}
