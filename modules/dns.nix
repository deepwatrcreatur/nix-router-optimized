{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router.dns;
in
{
  options.router.dns = {
    enable = mkEnableOption "DNS resolver configuration";

    provider = mkOption {
      type = types.enum [ "technitium" "unbound" "dnsmasq" ];
      default = "unbound";
      description = "DNS server software to use";
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      example = [ "192.168.1.1" "10.0.0.1" ];
      description = "Addresses to listen on for DNS queries";
    };

    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "Upstream DNS servers";
    };

    localZones = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        "router.local" = "192.168.1.1";
        "nas.local" = "192.168.1.10";
      };
      description = "Local DNS entries (hostname -> IP)";
    };
  };

  config = mkIf cfg.enable {
    # Unbound configuration
    services.unbound = mkIf (cfg.provider == "unbound") {
      enable = true;
      settings = {
        server = {
          interface = cfg.listenAddresses;
          access-control = [
            "127.0.0.0/8 allow"
            "10.0.0.0/8 allow"
            "172.16.0.0/12 allow"
            "192.168.0.0/16 allow"
          ];
          
          # Performance tuning
          num-threads = 4;
          msg-cache-slabs = 4;
          rrset-cache-slabs = 4;
          infra-cache-slabs = 4;
          key-cache-slabs = 4;
          
          # Cache sizes
          rrset-cache-size = "256m";
          msg-cache-size = "128m";
          
          # Privacy
          hide-identity = true;
          hide-version = true;
          
          # Local zones
          local-data = mapAttrsToList (host: ip: ''"${host}. A ${ip}"'') cfg.localZones;
        };
        
        forward-zone = [{
          name = ".";
          forward-addr = cfg.upstreamServers;
        }];
      };
    };

    # Dnsmasq configuration
    services.dnsmasq = mkIf (cfg.provider == "dnsmasq") {
      enable = true;
      settings = {
        listen-address = concatStringsSep "," cfg.listenAddresses;
        server = cfg.upstreamServers;
        
        # Performance
        cache-size = 10000;
        
        # Local hosts
        address = mapAttrsToList (host: ip: "/${host}/${ip}") cfg.localZones;
      };
    };
  };
}
