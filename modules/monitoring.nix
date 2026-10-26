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

  caddyIngressDashboard = {
    dashboard = {
      title = "Caddy Ingress & Access";
      timezone = "browser";
      schemaVersion = 16;
      version = 1;
      refresh = "5s";

      panels = [
        {
          id = 21;
          title = "Total Ingress Request Rate";
          type = "stat";
          gridPos = { x = 0; y = 0; w = 6; h = 4; };
          targets = [{
            expr = "sum(rate(caddy_http_requests_total[1m])) or 0";
            legendFormat = "Req/s";
          }];
          fieldConfig = {
            defaults = {
              unit = "reqps";
            };
          };
        }
        {
          id = 22;
          title = "p95 Ingress Latency";
          type = "gauge";
          gridPos = { x = 6; y = 0; w = 6; h = 4; };
          targets = [{
            expr = "histogram_quantile(0.95, sum by (le) (rate(caddy_http_request_duration_seconds_bucket[5m]))) * 1000 or 0";
            legendFormat = "p95";
          }];
          fieldConfig = {
            defaults = {
              unit = "ms";
            };
          };
        }
        {
          id = 23;
          title = "Handled HTTP Status Codes";
          type = "graph";
          gridPos = { x = 12; y = 0; w = 12; h = 8; };
          targets = [
            {
              expr = "sum by (code) (rate(caddy_http_responses_total[1m])) or sum by (status) (rate(caddy_http_requests_total[1m]))";
              legendFormat = "{{code}}{{status}}";
            }
          ];
        }
        {
          id = 24;
          title = "Ingress & Egress Bandwidth";
          type = "graph";
          gridPos = { x = 0; y = 4; w = 12; h = 8; };
          targets = [
            {
              expr = "sum(rate(caddy_http_response_size_bytes_sum[1m])) * 8 or 0";
              legendFormat = "Outbound (Served)";
            }
            {
              expr = "sum(rate(caddy_http_request_size_bytes_sum[1m])) * 8 or 0";
              legendFormat = "Inbound (Received)";
            }
          ];
          yaxes = [
            { format = "bps"; }
            { format = "short"; }
          ];
        }
        {
          id = 25;
          title = "Requests by Virtual Host";
          type = "graph";
          gridPos = { x = 0; y = 12; w = 14; h = 8; };
          targets = [
            {
              expr = "sum by (server_name) (rate(caddy_http_requests_total[1m]))";
              legendFormat = "{{server_name}}";
            }
          ];
        }
        {
          id = 26;
          title = "Upstream Backend Health";
          type = "stat";
          gridPos = { x = 14; y = 12; w = 10; h = 8; };
          targets = [
            {
              expr = "caddy_reverse_proxy_upstreams_healthy";
              legendFormat = "{{upstream}}";
            }
          ];
        }
      ];
    };
  };

  networkTelemetryDashboard = {
    dashboard = {
      title = "Network Telemetry & WAN Quality";
      timezone = "browser";
      schemaVersion = 16;
      version = 1;
      refresh = "5s";

      panels = [
        {
          id = 31;
          title = "Conntrack Table Saturation";
          type = "gauge";
          gridPos = { x = 0; y = 0; w = 6; h = 5; };
          targets = [{
            expr = "100 * (node_nf_conntrack_entries / node_nf_conntrack_entries_limit)";
            legendFormat = "Table %";
          }];
          fieldConfig = {
            defaults = {
              unit = "percent";
              thresholds = {
                mode = "absolute";
                steps = [
                  { color = "green"; value = null; }
                  { color = "yellow"; value = 70; }
                  { color = "red"; value = 85; }
                ];
              };
            };
          };
        }
        {
          id = 32;
          title = "Connection Churn (New Conn/s)";
          type = "graph";
          gridPos = { x = 6; y = 0; w = 9; h = 5; };
          targets = [
            {
              expr = "rate(node_netstat_Tcp_ActiveOpens[1m])";
              legendFormat = "Outbound TCP Opens/s";
            }
            {
              expr = "rate(node_netstat_Tcp_PassiveOpens[1m])";
              legendFormat = "Inbound TCP Opens/s";
            }
          ];
        }
        {
          id = 33;
          title = "TCP Retransmission Rate (%)";
          type = "gauge";
          gridPos = { x = 15; y = 0; w = 9; h = 5; };
          targets = [{
            expr = "(rate(node_netstat_Tcp_RetransSegs[1m]) / clamp_min(rate(node_netstat_Tcp_OutSegs[1m]), 1)) * 100";
            legendFormat = "Retransmit %";
          }];
          fieldConfig = {
            defaults = {
              unit = "percent";
            };
          };
        }
        {
          id = 34;
          title = "Interface Buffer FIFO Overruns & Carrier Errors";
          type = "graph";
          gridPos = { x = 0; y = 5; w = 12; h = 8; };
          targets = [
            {
              expr = "rate(node_network_receive_fifo_total{device=~\"${interfaceRegex}\"}[1m])";
              legendFormat = "{{device}} RX FIFO overruns";
            }
            {
              expr = "rate(node_network_transmit_fifo_total{device=~\"${interfaceRegex}\"}[1m])";
              legendFormat = "{{device}} TX FIFO overruns";
            }
            {
              expr = "rate(node_network_carrier_changes_total{device=~\"${interfaceRegex}\"}[5m])";
              legendFormat = "{{device}} Carrier state changes";
            }
          ];
        }
        {
          id = 35;
          title = "Hardware Temperature & SFP Sensor Telemetry";
          type = "graph";
          gridPos = { x = 12; y = 5; w = 12; h = 8; };
          targets = [
            {
              expr = "node_hwmon_temp_celsius";
              legendFormat = "{{chip}} - {{sensor}} (°C)";
            }
          ];
          yaxes = [
            { format = "celsius"; }
            { format = "short"; }
          ];
        }
        {
          id = 36;
          title = "ICMP & Network Control Traffic";
          type = "graph";
          gridPos = { x = 0; y = 13; w = 24; h = 7; };
          targets = [
            {
              expr = "rate(node_netstat_Icmp_InMsgs[1m])";
              legendFormat = "ICMP In msgs/s";
            }
            {
              expr = "rate(node_netstat_Icmp_OutMsgs[1m])";
              legendFormat = "ICMP Out msgs/s";
            }
            {
              expr = "rate(node_netstat_Icmp6_InMsgs[1m])";
              legendFormat = "ICMPv6 In msgs/s";
            }
            {
              expr = "rate(node_netstat_Icmp6_OutMsgs[1m])";
              legendFormat = "ICMPv6 Out msgs/s";
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
      ] ++ optional (config.services.router-kea.enable or config.services.kea.dhcp4.enable or false) {
        job_name = "kea";
        static_configs = [{
          targets = [ "localhost:${toString (config.services.router-kea.exporter.port or 9547)}" ];
        }];
      };

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
              {
                alert = "KeaDhcpPoolUtilizationWarning";
                expr = "kea_dhcp4_pool_utilization_percent > 75";
                for = "2m";
                labels.severity = "warning";
                annotations = {
                  summary = "Kea DHCP IP pool utilization warning (>75%)";
                  description = "Dynamic IP pool utilization is {{ $value }}% (threshold: 75%).";
                };
              }
              {
                alert = "KeaDhcpPoolUtilizationCritical";
                expr = "kea_dhcp4_pool_utilization_percent > 90";
                for = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "Kea DHCP IP pool utilization critical (>90%)";
                  description = "Dynamic IP pool utilization is {{ $value }}% (threshold: 90%).";
                };
              }
              {
                alert = "KeaDhcpDeclinedAddressesWarning";
                expr = "kea_dhcp4_declined_addresses > 5";
                for = "1m";
                labels.severity = "warning";
                annotations = {
                  summary = "Kea DHCP DECLINED address count high (>5)";
                  description = "Kea DHCP declined-addresses count is {{ $value }} (threshold: 5).";
                };
              }
              {
                alert = "KeaDhcpNakRateCritical";
                expr = "rate(kea_dhcp4_pkt4_nak_sent[1m]) * 60 > 10";
                for = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "Kea DHCP NAK rate critical (>10/min)";
                  description = "Kea DHCP pkt4-nak-sent rate is {{ $value }} NAKs/min (threshold: 10/min).";
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
          secret_key = lib.mkDefault "$__file{${cfg.grafanaDataDir}/.secret-key}";
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

      if [ -f "/etc/grafana/secret_key" ] && [ ! -f "${cfg.grafanaDataDir}/.secret-key" ]; then
        cp "/etc/grafana/secret_key" "${cfg.grafanaDataDir}/.secret-key"
        chmod 600 "${cfg.grafanaDataDir}/.secret-key"
      elif [ ! -f "${cfg.grafanaDataDir}/.secret-key" ]; then
        echo "SW2YcwTIb9zpOOhoPsMm" > "${cfg.grafanaDataDir}/.secret-key"
        chmod 600 "${cfg.grafanaDataDir}/.secret-key"
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

    environment.etc."grafana-dashboards/router-caddy-ingress.json" = {
      mode = "0644";
      text = builtins.toJSON caddyIngressDashboard;
    };

    environment.etc."grafana-dashboards/router-network-telemetry.json" = {
      mode = "0644";
      text = builtins.toJSON networkTelemetryDashboard;
    };

  };
}
