{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-observability;
in
{
  options.services.router-observability = {
    enable = mkEnableOption "flow logging and observability for the router";

    enableUlogd = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ulogd2 for netfilter flow logging.";
    };

    enableVector = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Vector for log and metric routing.";
    };

    ulogdGroup = mkOption {
      type = types.int;
      default = 1;
      description = "Netfilter NFLOG group for ulogd.";
    };

    exportMetrics = {
      enable = mkEnableOption "remote writing metrics to an external store";
      remoteWriteUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://victoria-metrics:8428/api/v1/write";
        description = "Prometheus remote write URL.";
      };
    };

    exportLogs = {
      enable = mkEnableOption "shipping flow logs to an external aggregator";
      upstreamVectorAddr = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "vector-central:6000";
        description = "Central Vector instance address.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.ulogd = mkIf cfg.enableUlogd {
      enable = true;
      settings = {
        global = {
          logfile = "/var/log/ulogd/ulogd.log";
          # Notice: plugin names must match exact .so filenames in pkgs.ulogd
          plugin = [
            "${pkgs.ulogd}/lib/ulogd/ulogd_inppkt_NFLOG.so"
            "${pkgs.ulogd}/lib/ulogd/ulogd_raw2packet_BASE.so"
            "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IFINDEX.so"
            "${pkgs.ulogd}/lib/ulogd/ulogd_filter_IP2STR.so"
            "${pkgs.ulogd}/lib/ulogd/ulogd_filter_PRINTPKT.so"
            "${pkgs.ulogd}/lib/ulogd/ulogd_output_LOGEMU.so"
          ];
          # Note: BASE matches ulogd_raw2packet_BASE.so
          # Note: LOGEMU matches ulogd_output_LOGEMU.so
          # We use LOGEMU because JSON output is not currently packaged in Nixpkgs
          stack = "log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU";
        };
        log1 = {
          group = cfg.ulogdGroup;
        };
        emu1 = {
          file = "/var/log/ulogd/flow.log";
          sync = 1;
        };
      };
    };

    # Ensure log directory exists
    systemd.services.ulogd.serviceConfig.LogsDirectory = "ulogd";

    services.prometheus = mkIf cfg.exportMetrics.enable {
      remoteWrite = [
        {
          url = cfg.exportMetrics.remoteWriteUrl;
          queue_config = {
            max_shards = 10;
            min_shards = 1;
            max_samples_per_send = 500;
            capacity = 10000;
          };
        }
      ];
    };

    services.vector = mkIf cfg.enableVector {
      enable = true;
      journaldAccess = true;
      settings = {
        sources.ulogd_log = {
          type = "file";
          include = [ "/var/log/ulogd/flow.log" ];
        };

        # TODO: Implement better parser for LOGEMU format if needed.
        # For now, we just ship it as a message.
        transforms.parse_ulogd = {
          type = "remap";
          inputs = [ "ulogd_log" ];
          source = ''
            .timestamp = now()
          '';
        };

        sinks.console = {
          type = "console";
          inputs = [ "parse_ulogd" ];
          encoding.codec = "json";
        };

        sinks.upstream = mkIf cfg.exportLogs.enable {
          type = "vector";
          inputs = [ "parse_ulogd" ];
          address = cfg.exportLogs.upstreamVectorAddr;
          version = "2";
        };
      };
    };
  };
}
