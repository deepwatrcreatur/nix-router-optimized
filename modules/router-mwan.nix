{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-mwan;
  networkingCfg = config.services.router-networking;

  wanHealthModule = types.submodule {
    options = {
      interface = mkOption {
        type = types.str;
        description = "The WAN interface to monitor.";
      };
      trackIp = mkOption {
        type = types.str;
        default = "8.8.8.8";
        description = "The IP address to ping for health checks.";
      };
      interval = mkOption {
        type = types.int;
        default = 5;
        description = "Check interval in seconds.";
      };
      failCount = mkOption {
        type = types.int;
        default = 3;
        description = "Number of failures before marking as down.";
      };
      recoveryCount = mkOption {
        type = types.int;
        default = 2;
        description = "Number of successes before marking as up.";
      };
      primaryMetric = mkOption {
        type = types.int;
        default = 100;
        description = "Route metric when healthy.";
      };
      failMetric = mkOption {
        type = types.int;
        default = 2000;
        description = "Route metric when unhealthy.";
      };
    };
  };

  # Script for monitoring and metric switching
  mwanScript = pkgs.writeShellScriptBin "router-mwan-monitor" ''
    set -euo pipefail
    
    # State tracking
    declare -A STATUS
    declare -A FAIL_COUNT
    declare -A SUCCESS_COUNT

    # Initialize
    ${concatMapStringsSep "\n" (wan: ''
      STATUS["${wan.interface}"]="up"
      FAIL_COUNT["${wan.interface}"]=0
      SUCCESS_COUNT["${wan.interface}"]=0
    '') cfg.interfaces}

    echo "Starting Multi-WAN monitor..."

    while true; do
      ${concatMapStringsSep "\n" (wan: ''
        # Check health of ${wan.interface}
        if ${pkgs.iputils}/bin/ping -c 1 -W 2 -I ${wan.interface} ${wan.trackIp} >/dev/null 2>&1; then
          SUCCESS_COUNT["${wan.interface}"]=$((SUCCESS_COUNT["${wan.interface}"] + 1))
          FAIL_COUNT["${wan.interface}"]=0
          
          if [[ ''${STATUS["${wan.interface}"]} == "down" && ''${SUCCESS_COUNT["${wan.interface}"]} -ge ${toString wan.recoveryCount} ]]; then
            echo "Interface ${wan.interface} RECOVERED. Setting metric to ${toString wan.primaryMetric}."
            ${pkgs.iproute2}/bin/ip route change default dev ${wan.interface} metric ${toString wan.primaryMetric} || \
            ${pkgs.iproute2}/bin/ip route add default dev ${wan.interface} metric ${toString wan.primaryMetric}
            STATUS["${wan.interface}"]="up"
          fi
        else
          FAIL_COUNT["${wan.interface}"]=$((FAIL_COUNT["${wan.interface}"] + 1))
          SUCCESS_COUNT["${wan.interface}"]=0
          
          if [[ ''${STATUS["${wan.interface}"]} == "up" && ''${FAIL_COUNT["${wan.interface}"]} -ge ${toString wan.failCount} ]]; then
            echo "Interface ${wan.interface} FAILED. Setting metric to ${toString wan.failMetric}."
            ${pkgs.iproute2}/bin/ip route change default dev ${wan.interface} metric ${toString wan.failMetric} || \
            ${pkgs.iproute2}/bin/ip route add default dev ${wan.interface} metric ${toString wan.failMetric}
            STATUS["${wan.interface}"]="down"
          fi
        fi
      '') cfg.interfaces}
      
      sleep ${toString cfg.checkInterval};
    done
  '';
in
{
  options.services.router-mwan = {
    enable = mkEnableOption "Multi-WAN health monitoring and failover";

    checkInterval = mkOption {
      type = types.int;
      default = 5;
      description = "Global check interval in seconds.";
    };

    interfaces = mkOption {
      type = types.listOf wanHealthModule;
      default = [ ];
      description = "List of WAN interfaces to monitor.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.router-mwan = {
      description = "Multi-WAN Health Monitor";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${mwanScript}/bin/router-mwan-monitor";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
