{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-dns-service;

  effectiveNameservers = unique (cfg.listenAddresses ++ cfg.fallbackNameservers);
  effectiveServiceListenAddresses =
    if cfg.serviceListenAddresses != [ ] then unique cfg.serviceListenAddresses else cfg.listenAddresses;

  resolvConfText =
    let
      searchLine =
        optionalString (cfg.searchDomains != [ ]) "search ${concatStringsSep " " cfg.searchDomains}\n";
      nameserverLines = concatMapStrings (addr: "nameserver ${addr}\n") effectiveNameservers;
    in
    searchLine + nameserverLines;
in
{
  imports = [
    ./dns.nix
    ./router-technitium.nix
  ];

  options.services.router-dns-service = {
    enable = mkEnableOption "router-oriented DNS service defaults";

    provider = mkOption {
      type = types.enum [ "technitium" "unbound" "dnsmasq" ];
      default = "technitium";
      description = "DNS provider to run on the router.";
    };

    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "Local resolver addresses preferred by the router itself.";
    };

    serviceListenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "127.0.0.1" "10.10.10.1" ];
      description = ''
        Addresses the DNS service itself should bind to.

        Leave empty to keep the provider default behavior. Non-Technitium
        providers fall back to `listenAddresses`; Technitium keeps its upstream
        wildcard listener configuration unless explicitly overridden.
      '';
    };

    fallbackNameservers = mkOption {
      type = types.listOf types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "Fallback resolvers kept in resolv.conf for local host resilience.";
    };

    searchDomains = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Search domains written into resolv.conf when writeResolvConf is enabled.";
    };

    disableResolved = mkOption {
      type = types.bool;
      default = true;
      description = "Disable systemd-resolved and rely on the chosen router DNS service directly.";
    };

    writeResolvConf = mkOption {
      type = types.bool;
      default = true;
      description = "Write a static /etc/resolv.conf using listenAddresses and fallbackNameservers.";
    };

    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "Upstream DNS servers for non-Technitium providers.";
    };

    localZones = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Simple local DNS records for non-Technitium providers.";
    };

    technitium = {
      apiKeySecretName = mkOption {
        type = types.nullOr types.str;
        default = "technitium-api-key";
        description = "Age secret name exported as TECHNITIUM_API_KEY_FILE for Technitium.";
      };

      enableBlockLists = mkOption {
        type = types.bool;
        default = true;
        description = "Enable declarative Technitium block list synchronization.";
      };

      blockListPresets = mkOption {
        type = types.listOf types.str;
        default = [ "hagezi-normal" ];
        description = "Technitium block list presets.";
      };

      extraBlockListUrls = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional Technitium block list URLs.";
      };

      blockListUpdateIntervalHours = mkOption {
        type = types.ints.between 1 168;
        default = 24;
        description = "Technitium block list refresh interval in hours.";
      };

      forceBlockListUpdateOnActivation = mkOption {
        type = types.bool;
        default = true;
        description = "Force a block list refresh when the Technitium sync service runs.";
      };
    };

    ntpServers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.10.1" ];
      description = ''
        NTP server addresses to advertise via DHCP option 42.
        Passed through to services.router-technitium.ntpServers when
        provider = "technitium".
      '';
    };
  };

  config = mkIf cfg.enable {
    services.resolved.enable = mkIf cfg.disableResolved false;

    networking.nameservers = mkDefault effectiveNameservers;

    environment.etc."resolv.conf" = mkIf cfg.writeResolvConf {
      text = resolvConfText;
    };

    router.dns = mkIf (cfg.provider != "technitium") {
      enable = true;
      provider = cfg.provider;
      listenAddresses = effectiveServiceListenAddresses;
      upstreamServers = cfg.upstreamServers;
      localZones = cfg.localZones;
    };

    services.router-technitium = mkIf (cfg.provider == "technitium") {
      enable = true;
      apiKeySecretName = cfg.technitium.apiKeySecretName;
      enableBlockLists = cfg.technitium.enableBlockLists;
      blockListPresets = cfg.technitium.blockListPresets;
      extraBlockListUrls = cfg.technitium.extraBlockListUrls;
      blockListUpdateIntervalHours = cfg.technitium.blockListUpdateIntervalHours;
      forceBlockListUpdateOnActivation = cfg.technitium.forceBlockListUpdateOnActivation;
      listenEndPoints = map (addr: "${addr}:53") cfg.serviceListenAddresses;
      ntpServers = cfg.ntpServers;
    };
  };
}
