{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-ntopng;
  hasRouterOption = path: hasAttrByPath path options;
  optimizationInterfaces =
    if hasRouterOption [ "services" "router-optimizations" "interfaces" ] then
      config.services.router-optimizations.interfaces or { }
    else
      { };
  routedIfaces =
    if hasRouterOption [ "services" "router-networking" "routedInterfaces" ] then
      config.services.router-networking.routedInterfaces or { }
    else
      { };

  stripCidr = addr: builtins.head (splitString "/" addr);

  defaultListenAddress =
    if cfg.listenAddress != null then
      cfg.listenAddress
    else if routedIfaces ? lan then
      stripCidr routedIfaces.lan.ipv4Address
    else if routedIfaces != { } then
      stripCidr ((builtins.head (attrValues routedIfaces)).ipv4Address)
    else
      "0.0.0.0";

  effectiveInterfaces =
    if cfg.interfaces != [ ] || !cfg.autoInterfacesFromOptimizations then
      cfg.interfaces
    else
      unique (mapAttrsToList (_name: iface: iface.device) optimizationInterfaces);

  httpListenSpec =
    if defaultListenAddress == "0.0.0.0" then
      toString cfg.port
    else
      "${defaultListenAddress}:${toString cfg.port}";

  waitForListenAddressScript = pkgs.writeShellScript "wait-for-router-ntopng-address" ''
    set -eu

    addr="$1"
    addr_pattern=$(printf '%s\n' "$addr" | ${pkgs.gnused}/bin/sed 's/\./\\./g')

    for _ in $(seq 1 ${toString cfg.waitForListenAddressTimeout}); do
      if ${pkgs.gnugrep}/bin/grep -Eq "[[:space:]]$addr_pattern(/32)?([[:space:]]|$)" /proc/net/fib_trie; then
        exit 0
      fi
      sleep 1
    done

    echo "Timed out waiting for IPv4 address $addr" >&2
    exit 1
  '';

in
{
  options.services.router-ntopng = {
    enable = mkEnableOption "router-oriented ntopng traffic analysis";

    interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "eth0" "eth1" ];
      description = "Interfaces monitored by ntopng.";
    };

    autoInterfacesFromOptimizations = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, derive monitored interfaces from
        services.router-optimizations.interfaces if no explicit interface list
        is set here.
      '';
    };

    listenAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "IPv4 address ntopng should bind its web UI to.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "HTTP port for the ntopng web UI.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the ntopng web UI on trusted router firewall interfaces.";
    };

    waitForListenAddress = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wait until the chosen listenAddress exists before starting ntopng.
        This helps on routers that bind services to a specific interface IP.
      '';
    };

    waitForListenAddressTimeout = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum number of seconds to wait for the ntopng listen address.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional ntopng configuration lines appended to the generated config.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.ntopng = {
        enable = true;
        interfaces = effectiveInterfaces;
        httpPort = cfg.port;
        configText = ''
          ${concatStringsSep "\n" (map (iface: "--interface=${iface}") effectiveInterfaces)}
          --http-port=${httpListenSpec}
          --redis=${config.services.ntopng.redis.address}
          --data-dir=/var/lib/ntopng
          --user=ntopng
          ${cfg.extraConfig}
        '';
      };

      systemd.services.ntopng = mkIf (cfg.waitForListenAddress && defaultListenAddress != "0.0.0.0") {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        preStart = mkBefore ''
          ${waitForListenAddressScript} ${escapeShellArg defaultListenAddress}
        '';
      };
    }

    (mkIf (cfg.openFirewall && hasRouterOption [ "services" "router-firewall" "trustedTcpPorts" ]) {
      services.router-firewall.trustedTcpPorts = [ cfg.port ];
    })
  ]);
}
