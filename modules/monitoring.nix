{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.router.monitoring;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };
  grafanaDashboardsDir =
    if cfg.grafanaDashboardsDir != null then cfg.grafanaDashboardsDir else "${cfg.grafanaDataDir}/dashboards";
  prometheusStatePath = "/var/lib/${cfg.prometheusStateDir}";

  effectiveInterfaces =
    if cfg.interfaces != [ ] || !cfg.autoInterfacesFromOptimizations then
      cfg.interfaces
    else
      mapAttrsToList (_name: iface: iface.device) optimizationInterfaces;
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
      retentionTime = "30d";
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
          admin_password = "$__file{/run/grafana/admin-password}";
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
          options.path = grafanaDashboardsDir;
        }];
      };
    };

    # Create admin password file
    systemd.services.grafana.preStart = ''
      mkdir -p /run/grafana
      if [ ! -f /run/grafana/admin-password ]; then
        echo "admin" > /run/grafana/admin-password
      fi
      chmod 600 /run/grafana/admin-password
    '';

    fileSystems.${prometheusStatePath} = mkIf (cfg.prometheusBindMountPath != null) {
      device = cfg.prometheusBindMountPath;
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
      depends = [ (builtins.dirOf cfg.prometheusBindMountPath) ];
    };

    # Install pre-built router dashboards
    systemd.tmpfiles.rules = [
      "d ${grafanaDashboardsDir} 0755 grafana grafana -"
    ];

    environment.etc."grafana-dashboards/router-overview.json" = {
      mode = "0644";
      text = builtins.toJSON {
        dashboard = {
          title = "Router Overview";
          timezone = "browser";
          schemaVersion = 16;
          version = 0;
          refresh = "5s";

          panels = [
            {
              id = 1;
              title = "Network Traffic";
              type = "graph";
              gridPos = { x = 0; y = 0; w = 12; h = 8; };
              targets = [
                {
                  expr = "rate(node_network_receive_bytes_total{device=~\"${concatStringsSep "|" effectiveInterfaces}\"}[1m]) * 8";
                  legendFormat = "{{device}} RX";
                }
                {
                  expr = "rate(node_network_transmit_bytes_total{device=~\"${concatStringsSep "|" effectiveInterfaces}\"}[1m]) * 8";
                  legendFormat = "{{device}} TX";
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
              gridPos = { x = 12; y = 0; w = 6; h = 4; };
              targets = [{
                expr = "node_nf_conntrack_entries";
              }];
            }
            {
              id = 3;
              title = "CPU Usage";
              type = "gauge";
              gridPos = { x = 18; y = 0; w = 6; h = 4; };
              targets = [{
                expr = "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[1m])) * 100)";
              }];
            }
            {
              id = 4;
              title = "Memory Usage";
              type = "gauge";
              gridPos = { x = 12; y = 4; w = 6; h = 4; };
              targets = [{
                expr = "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))";
              }];
            }
            {
              id = 5;
              title = "System Uptime";
              type = "stat";
              gridPos = { x = 18; y = 4; w = 6; h = 4; };
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
              id = 6;
              title = "Packet Errors";
              type = "graph";
              gridPos = { x = 0; y = 8; w = 12; h = 8; };
              targets = [
                {
                  expr = "rate(node_network_receive_errs_total{device=~\"${concatStringsSep "|" effectiveInterfaces}\"}[1m])";
                  legendFormat = "{{device}} RX errors";
                }
                {
                  expr = "rate(node_network_transmit_errs_total{device=~\"${concatStringsSep "|" effectiveInterfaces}\"}[1m])";
                  legendFormat = "{{device}} TX errors";
                }
              ];
            }
            {
              id = 7;
              title = "Conntrack Table Usage";
              type = "graph";
              gridPos = { x = 12; y = 8; w = 12; h = 8; };
              targets = [
                {
                  expr = "node_nf_conntrack_entries";
                  legendFormat = "Current connections";
                }
                {
                  expr = "node_nf_conntrack_entries_limit";
                  legendFormat = "Max connections";
                }
              ];
            }
          ];
        };
      };
    };

    # Copy dashboard to Grafana
    systemd.services.grafana-setup-dashboards = {
      description = "Copy Grafana dashboards";
      after = [ "grafana.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p ${grafanaDashboardsDir}
        cp /etc/grafana-dashboards/*.json ${grafanaDashboardsDir}/ || true
        chown -R grafana:grafana ${grafanaDashboardsDir}
      '';
    };
  };
}
