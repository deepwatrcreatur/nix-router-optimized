{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-homelab;
  hasRouterOption = path: hasAttrByPath path options;
  routedIfaces =
    if hasRouterOption [ "services" "router-networking" "routedInterfaces" ] then
      config.services.router-networking.routedInterfaces or { }
    else
      { };
  waitForListenAddressScript = pkgs.writeShellScript "wait-for-router-homelab-address" ''
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

  dashboardLinks =
    (optionals cfg.enableNetdata [
      {
        label = "Netdata";
        url = "http://${defaultListenAddress}:19999/";
        icon = "📊";
      }
    ])
    ++ (optionals cfg.enableMonitoring [
      {
        label = "Grafana";
        url = "http://${defaultListenAddress}:${toString cfg.grafanaPort}/";
        icon = "📈";
      }
    ])
    ++ (optionals (config.services.router-ntopng.enable or false) [
      {
        label = "Traffic";
        url = "http://${defaultListenAddress}:${toString config.services.router-ntopng.port}/";
        icon = "🛰️";
      }
    ])
    ++ (optionals (config.services.technitium-dns-server.enable or false) [
      {
        label = "DNS Admin";
        url = "http://${defaultListenAddress}:5380/";
        icon = "🌍";
      }
    ])
    ++ (optionals (cfg.sshTarget != null) [
      {
        label = "Router SSH";
        kind = "copy";
        copyText = cfg.sshTarget;
        icon = "🖥️";
      }
    ]);

  dashboardServices =
    [
      "nftables"
      "router-dashboard"
    ]
    ++ optionals cfg.enableMonitoring [
      "prometheus"
      "grafana"
    ]
    ++ optionals (config.services.router-ntopng.enable or false) [ "ntopng" ]
    ++ optionals cfg.enableNetdata [ "netdata" ]
    ++ optionals (config.services.technitium-dns-server.enable or false) [ "technitium-dns-server" ]
    ++ optionals (config.services.caddy.enable or false) [ "caddy" ];

  commonTrustedTcpPorts =
    [ 8888 ]
    ++ optionals cfg.enableMonitoring [ cfg.prometheusPort cfg.grafanaPort ]
    ++ optionals cfg.enableNetdata [ 19999 ]
    ++ optionals (config.services.technitium-dns-server.enable or false) [ 5380 53443 ];
in
{
  imports = [
    ./router-dashboard.nix
    ./monitoring.nix
    ./router-ntopng.nix
  ];

  options.services.router-homelab = {
    enable = mkEnableOption "small homelab router service bundle";

    listenAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Primary LAN address used for monitoring and dashboard links.";
    };

    sshTarget = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional SSH command copied by the dashboard quick-link.";
    };

    enableMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Prometheus/Grafana router monitoring bundle.";
    };

    enableNetdata = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Netdata with sensible LAN-only defaults.";
    };

    enableNtopng = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ntopng with router-aware defaults.";
    };

    grafanaPort = mkOption {
      type = types.port;
      default = 3001;
      description = "Grafana port when the monitoring bundle is enabled.";
    };

    prometheusPort = mkOption {
      type = types.port;
      default = 9090;
      description = "Prometheus port when the monitoring bundle is enabled.";
    };

    netdataAllowConnectionsFrom = mkOption {
      type = types.str;
      default = "10.0.*";
      description = "Netdata allow-list expression for browser access.";
    };

    waitForListenAddress = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wait until the derived listenAddress exists before starting LAN-bound
        monitoring services in this profile. This helps when the router binds
        services to a specific interface address instead of 0.0.0.0.
      '';
    };

    waitForListenAddressTimeout = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum number of seconds to wait for the homelab listen address.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.router-dashboard.enable = mkDefault true;
      services.router-dashboard.port = mkDefault 8888;
      services.router-dashboard.services = mkDefault dashboardServices;
      services.router-dashboard.links = mkAfter dashboardLinks;

      router.monitoring = mkIf cfg.enableMonitoring {
        enable = mkDefault true;
        listenAddress = mkDefault defaultListenAddress;
        waitForListenAddress = mkDefault cfg.waitForListenAddress;
        waitForListenAddressTimeout = mkDefault cfg.waitForListenAddressTimeout;
        prometheusPort = mkDefault cfg.prometheusPort;
        grafanaPort = mkDefault cfg.grafanaPort;
      };

      services.netdata = mkIf cfg.enableNetdata {
        enable = mkDefault true;
        package = mkDefault pkgs.netdataCloud;
        config = mkDefault {
          global = {
            "default port" = "19999";
            "bind to" = defaultListenAddress;
          };
          web = {
            "allow connections from" = cfg.netdataAllowConnectionsFrom;
            "allow dashboard from" = cfg.netdataAllowConnectionsFrom;
          };
        };
      };

      systemd.services.netdata = mkIf (cfg.enableNetdata && cfg.waitForListenAddress && defaultListenAddress != "0.0.0.0") {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        preStart = mkBefore ''
          ${waitForListenAddressScript} ${escapeShellArg defaultListenAddress}
        '';
      };

      services.router-ntopng = mkIf cfg.enableNtopng {
        enable = mkDefault true;
        listenAddress = mkDefault defaultListenAddress;
        waitForListenAddress = mkDefault cfg.waitForListenAddress;
        waitForListenAddressTimeout = mkDefault cfg.waitForListenAddressTimeout;
      };
    })

    (optionalAttrs (hasRouterOption [ "services" "router-firewall" "trustedTcpPorts" ]) (
      mkIf cfg.enable {
        services.router-firewall.trustedTcpPorts = mkAfter commonTrustedTcpPorts;
        services.router-firewall.wanTcpPorts = mkAfter (
          optionals (config.services.caddy.enable or false) [ 80 443 ]
        );
      }
    ))
  ];
}
