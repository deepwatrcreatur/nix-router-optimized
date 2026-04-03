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
  };

  config = mkIf cfg.enable {
    services.ulogd = mkIf cfg.enableUlogd {
      enable = true;
      settings = ''
        [global]
        logfile="/var/log/ulogd/ulogd.log"
        loglevel=5
        plugin="${pkgs.ulogd}/lib/ulogd/ulogd_inppkt_NFLOG.so"
        plugin="${pkgs.ulogd}/lib/ulogd/ulogd_filter_IFINDEX.so"
        plugin="${pkgs.ulogd}/lib/ulogd/ulogd_filter_IP2STR.so"
        plugin="${pkgs.ulogd}/lib/ulogd/ulogd_filter_PRINTPKT.so"
        plugin="${pkgs.ulogd}/lib/ulogd/ulogd_output_JSON.so"

        stack=log1:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,json1:JSON

        [log1]
        group=${toString cfg.ulogdGroup}

        [json1]
        file="/var/log/ulogd/flow.json"
        sync=1
      '';
    };

    # Ensure log directory exists
    systemd.services.ulogd.serviceConfig.LogsDirectory = "ulogd";

    services.vector = mkIf cfg.enableVector {
      enable = true;
      journaldAccess = true;
      settings = {
        sources.ulogd_json = {
          type = "file";
          include = [ "/var/log/ulogd/flow.json" ];
        };

        transforms.parse_ulogd = {
          type = "remap";
          inputs = [ "ulogd_json" ];
          source = ''
            . = parse_json!(.message)
            .timestamp = parse_timestamp!(.timestamp, "%Y-%m-%dT%H:%M:%S%.f%z")
          '';
        };

        sinks.console = {
          type = "console";
          inputs = [ "parse_ulogd" ];
          encoding.codec = "json";
        };
      };
    };
  };
}
