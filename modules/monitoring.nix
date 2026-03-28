{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router.monitoring;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };
  grafanaDashboardsDir =
    if cfg.grafanaDashboardsDir != null then cfg.grafanaDashboardsDir else "${cfg.grafanaDataDir}/dashboards";
  prometheusStatePath = "/var/lib/${cfg.prometheusStateDir}";
  interfaceRegex = concatStringsSep "|" effectiveInterfaces;
  waitForListenAddressScript = pkgs.writeShellScript "wait-for-router-monitoring-address" ''
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

  effectiveInterfaces =
    if cfg.interfaces != [ ] || !cfg.autoInterfacesFromOptimizations then
      cfg.interfaces
    else
      mapAttrsToList (_name: iface: iface.device) optimizationInterfaces;

  overviewDashboard = {
    dashboard = {
      title = "Router Overview";
      timezone = "browser";
      schemaVersion = 16;
      version = 1;
      refresh = "5s";

      panels = [
        {
          id = 1;
          title = "Aggregate Network Traffic";
          type = "graph";
          gridPos = { x = 0; y = 0; w = 12; h = 8; };
          targets = [
            {
              expr = "sum(rate(node_network_receive_bytes_total{device=~\"${interfaceRegex}\"}[1m])) * 8";
              legendFormat = "RX";
            }
            {
              expr = "sum(rate(node_network_transmit_bytes_total{device=~\"${interfaceRegex}\"}[1m])) * 8";
              legendFormat = "TX";
            }
          ];
          yaxes = [
            { format = "bps"; }
            { format = "short"; }
          ];
        }
        {
          id = 2;
          title = "Active Connections";
          type = "stat";
          gridPos = { x = 12; y = 0; w = 4; h = 4; };
          targets = [{
            expr = "node_nf_conntrack_entries";
          }];
        }
        {
          id = 3;
          title = "Conntrack Utilization";
          type = "gauge";
          gridPos = { x = 16; y = 0; w = 4; h = 4; };
          targets = [{
            expr = "100 * (node_nf_conntrack_entries / node_nf_conntrack_entries_limit)";
          }];
        }
        {
          id = 4;
          title = "CPU Usage";
          type = "gauge";
          gridPos = { x = 20; y = 0; w = 4; h = 4; };
          targets = [{
            expr = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[1m])) * 100)";
          }];
        }
        {
          id = 5;
          title = "Memory Usage";
          type = "gauge";
          gridPos = { x = 12; y = 4; w = 4; h = 4; };
          targets = [{
            expr = "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))";
          }];
        }
        {
          id = 6;
          title = "Root Filesystem Usage";
          type = "gauge";
          gridPos = { x = 16; y = 4; w = 4; h = 4; };
          targets = [{
            expr = "100 * (1 - (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}))";
          }];
        }
        {
          id = 7;
          title = "System Uptime";
          type = "stat";
          gridPos = { x = 20; y = 4; w = 4; h = 4; };
          targets = [{
            expr = "node_time_seconds - node_boot_time_seconds";
          }];
          fieldConfig = {
            defaults = {
              unit = "s";
            };
          };
        }
        {
          id = 8;
          title = "Packet Errors";
          type = "graph";
          gridPos = { x = 0; y = 8; w = 12; h = 8; };
          targets = [
            {
              expr = "sum(rate(node_network_receive_errs_total{device=~\"${interfaceRegex}\"}[5m]))";
              legendFormat = "RX errors";
            }
            {
              expr = "sum(rate(node_network_transmit_errs_total{device=~\"${interfaceRegex}\"}[5m]))";
              legendFormat = "TX errors";
            }
          ];
        }
        {
          id = 9;
          title = "Packet Drops";
          type = "graph";
          gridPos = { x = 12; y = 8; w = 12; h = 8; };
          targets = [
            {
              expr = "sum(rate(node_network_receive_drop_total{device=~\"${interfaceRegex}\"}[5m]))";
              legendFormat = "RX drops";
            }
            {
              expr = "sum(rate(node_network_transmit_drop_total{device=~\"${interfaceRegex}\"}[5m]))";
              legendFormat = "TX drops";
            }
          ];
        }
      ];
    };
  };

  interfaceDashboard = {
    dashboard = {
      title = "Router Interfaces";
      timezone = "browser";
      schemaVersion = 16;
      version = 1;
      refresh = "5s";

      panels = [
        {
          id = 11;
          title = "Per-Interface Throughput";
          type = "graph";
          gridPos = { x = 0; y = 0; w = 24; h = 9; };
          targets = [
            {
              expr = "rate(node_network_receive_bytes_total{device=~\"${interfaceRegex}\"}[1m]) * 8";
              legendFormat = "{{device}} RX";
            }
            {
              expr = "rate(node_network_transmit_bytes_total{device=~\"${interfaceRegex}\"}[1m]) * 8";
              legendFormat = "{{device}} TX";
            }
          ];
          yaxes = [
            { format = "bps"; }
            { format = "short"; }
          ];
        }
        {
          id = 12;
          title = "Per-Interface Packet Rate";
          type = "graph";
          gridPos = { x = 0; y = 9; w = 12; h = 8; };
          targets = [
            {
              expr = "rate(node_network_receive_packets_total{device=~\"${interfaceRegex}\"}[1m])";
              legendFormat = "{{device}} RX packets";
            }
            {
              expr = "rate(node_network_transmit_packets_total{device=~\"${interfaceRegex}\"}[1m])";
              legendFormat = "{{device}} TX packets";
            }
          ];
        }
        {
          id = 13;
          title = "Per-Interface Errors and Drops";
          type = "graph";
          gridPos = { x = 12; y = 9; w = 12; h = 8; };
          targets = [
            {
              expr = "rate(node_network_receive_errs_total{device=~\"${interfaceRegex}\"}[5m])";
              legendFormat = "{{device}} RX errors";
            }
            {
              expr = "rate(node_network_transmit_errs_total{device=~\"${interfaceRegex}\"}[5m])";
              legendFormat = "{{device}} TX errors";
            }
            {
              expr = "rate(node_network_receive_drop_total{device=~\"${interfaceRegex}\"}[5m])";
              legendFormat = "{{device}} RX drops";
            }
            {
              expr = "rate(node_network_transmit_drop_total{device=~\"${interfaceRegex}\"}[5m])";
              legendFormat = "{{device}} TX drops";
            }
          ];
        }
        {
          id = 14;
          title = "Load Average";
          type = "graph";
          gridPos = { x = 0; y = 17; w = 8; h = 6; };
          targets = [
            {
              expr = "node_load1";
              legendFormat = "1m";
            }
            {
              expr = "node_load5";
              legendFormat = "5m";
            }
            {
              expr = "node_load15";
              legendFormat = "15m";
            }
          ];
        }
        {
          id = 15;
          title = "CPU Mode Split";
          type = "graph";
          gridPos = { x = 8; y = 17; w = 8; h = 6; };
          targets = [
            {
              expr = "avg(rate(node_cpu_seconds_total{mode=\"system\"}[5m])) * 100";
              legendFormat = "system";
            }
            {
              expr = "avg(rate(node_cpu_seconds_total{mode=\"user\"}[5m])) * 100";
              legendFormat = "user";
            }
            {
              expr = "avg(rate(node_cpu_seconds_total{mode=\"iowait\"}[5m])) * 100";
              legendFormat = "iowait";
            }
          ];
        }
        {
          id = 16;
          title = "Memory Pressure";
          type = "graph";
          gridPos = { x = 16; y = 17; w = 8; h = 6; };
          targets = [
            {
              expr = "node_memory_MemAvailable_bytes";
              legendFormat = "available";
            }
            {
              expr = "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes";
              legendFormat = "used";
            }
          ];
        }
      ];
    };
  };
in
{
  options.router.monitoring = {
    enable = mkEnableOption "router monitoring stack (Prometheus + Grafana)";

    grafanaPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    prometheusPort = mkOption {
      type = types.port;
      default = 9090;
      description = "Port for Prometheus web interface";
    };

    prometheusRetentionTime = mkOption {
      type = types.str;
      default = "30d";
      example = "14d";
      description = ''
        Time-based retention for Prometheus TSDB data. Prometheus deletes old
        blocks when this age is exceeded.
      '';
    };

    prometheusRetentionSize = mkOption {
      type = types.nullOr types.str;
      default = "5GB";
      example = "20GB";
      description = ''
        Optional size-based retention limit for Prometheus TSDB data. This is
        the main safeguard against secondary log volumes filling up on smaller
        router systems.
      '';
    };

    interfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "eth0" "eth1" ];
      description = "Network interfaces to monitor";
    };

    autoInterfacesFromOptimizations = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, derive monitored interface devices from
        services.router-optimizations.interfaces if no explicit interface list
        is set here.
      '';
    };

    grafanaDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "grafana.example.com";
      description = "Domain for Grafana (for reverse proxy setup)";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "IP address to bind monitoring services to";
    };

    waitForListenAddress = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wait until listenAddress is present on the host before starting
        Prometheus and Grafana. Useful when services bind to a specific LAN
        address that may appear after network-online.target.
      '';
    };

    waitForListenAddressTimeout = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum number of seconds to wait for listenAddress.";
    };

    grafanaDataDir = mkOption {
      type = types.str;
      default = "/var/lib/grafana";
      description = "Grafana data directory. Set this to move Grafana state onto secondary storage.";
    };

    grafanaDashboardsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Directory where provisioned Grafana dashboards are copied. Defaults to <grafanaDataDir>/dashboards.";
    };

    prometheusStateDir = mkOption {
      type = types.str;
      default = "prometheus";
      description = ''
        Prometheus state directory name under /var/lib. Change this when you
        want a dedicated bind mount for Prometheus data.
      '';
    };

    prometheusBindMountPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional absolute path bound onto /var/lib/<prometheusStateDir> so
        Prometheus TSDB data can live on secondary storage.
      '';
    };

    alerting = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable built-in Prometheus alerting rules for common router health conditions.";
      };

      conntrackThreshold = mkOption {
        type = types.float;
        default = 0.8;
        description = "Conntrack utilization fraction (0.0–1.0) above which an alert fires.";
      };

      memoryThreshold = mkOption {
        type = types.float;
        default = 0.9;
        description = "Memory utilization fraction (0.0–1.0) above which an alert fires.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Prometheus for metrics collection
    services.prometheus = {
      enable = true;
      port = cfg.prometheusPort;
      listenAddress = cfg.listenAddress;
      stateDir = cfg.prometheusStateDir;

      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" "processes" "network_route" "conntrack" ];
          port = 9100;
        };
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
      ];

      # Retention settings
      retentionTime = cfg.prometheusRetentionTime;
      extraFlags = optional (cfg.prometheusRetentionSize != null) "--storage.tsdb.retention.size=${cfg.prometheusRetentionSize}";

      rules = mkIf cfg.alerting.enable [
        (builtins.toJSON {
          groups = [{
            name = "router";
            rules = [
              {
                alert = "ConntrackSaturation";
                expr = "node_nf_conntrack_entries / node_nf_conntrack_entries_limit > ${toString cfg.alerting.conntrackThreshold}";
                for = "2m";
                labels.severity = "warning";
                annotations = {
                  summary = "Conntrack table near capacity";
                  description = "Conntrack utilization is {{ humanizePercentage $value }} (threshold: ${toString (cfg.alerting.conntrackThreshold * 100)}%).";
                };
              }
              {
                alert = "HighMemoryUsage";
                expr = "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > ${toString cfg.alerting.memoryThreshold}";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "High memory usage";
                  description = "Memory utilization is {{ humanizePercentage $value }} (threshold: ${toString (cfg.alerting.memoryThreshold * 100)}%).";
                };
              }
              {
                alert = "NetworkInterfaceErrors";
                expr = "rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]) > 10";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Network interface errors on {{ $labels.device }}";
                  description = "Interface {{ $labels.device }} is experiencing {{ $value | humanize }} errors/s.";
                };
              }
            ];
          }];
        })
      ];
    };

    # Grafana for visualization
    services.grafana = {
      enable = true;
      dataDir = cfg.grafanaDataDir;
      settings = {
        server = {
          http_port = cfg.grafanaPort;
          http_addr = cfg.listenAddress;
          domain = if cfg.grafanaDomain != null then cfg.grafanaDomain else "localhost";
        };
        security = {
          admin_user = "admin";
          # Password stored in persistent state dir so it survives reboots
          admin_password = "$__file{${cfg.grafanaDataDir}/.admin-password}";
        };
        analytics.reporting_enabled = false;
      };

      provision = {
        enable = true;
        datasources.settings.datasources = [{
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString cfg.prometheusPort}";
          isDefault = true;
        }];

        dashboards.settings.providers = [{
          name = "Router Dashboards";
          # Point directly at the environment.etc path so dashboards are
          # available before Grafana starts, eliminating the provisioning race.
          options.path = "/etc/grafana-dashboards";
        }];
      };
    };

    # Generate a random admin password on first boot and store it persistently.
    # The file survives reboots in grafanaDataDir (/var/lib/grafana by default).
    # To rotate: delete the file and restart grafana.
    systemd.services.grafana.preStart = ''
      if [ ! -f "${cfg.grafanaDataDir}/.admin-password" ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 24 > "${cfg.grafanaDataDir}/.admin-password"
        chmod 600 "${cfg.grafanaDataDir}/.admin-password"
        echo "Generated new Grafana admin password in ${cfg.grafanaDataDir}/.admin-password"
      fi
    '' + optionalString (cfg.waitForListenAddress && cfg.listenAddress != "0.0.0.0") ''
      ${waitForListenAddressScript} ${escapeShellArg cfg.listenAddress}
    '';

    systemd.services.prometheus = mkIf (cfg.waitForListenAddress && cfg.listenAddress != "0.0.0.0") {
      preStart = mkBefore ''
        ${waitForListenAddressScript} ${escapeShellArg cfg.listenAddress}
      '';
    };

    fileSystems.${prometheusStatePath} = mkIf (cfg.prometheusBindMountPath != null) {
      device = cfg.prometheusBindMountPath;
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
      depends = [ (builtins.dirOf cfg.prometheusBindMountPath) ];
    };

    environment.etc."grafana-dashboards/router-overview.json" = {
      mode = "0644";
      text = builtins.toJSON overviewDashboard;
    };

    environment.etc."grafana-dashboards/router-interfaces.json" = {
      mode = "0644";
      text = builtins.toJSON interfaceDashboard;
    };

  };
}
