{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-mwan;
  networkingCfg = config.services.router-networking;
  hasRouterNptv6 = hasAttrByPath [ "services" "router-nptv6" "enable" ] options;
  nptv6Enabled = hasRouterNptv6 && (config.services.router-nptv6.enable or false);

  # Count how many WAN uplinks accept IPv6 router advertisements.
  primaryWanIPv6 = networkingCfg.wan.ipv6AcceptRA or false;
  additionalWansIPv6 = filter (w: w.ipv6AcceptRA or false) (attrValues (networkingCfg.wans or { }));
  ipv6WanCount = (if primaryWanIPv6 then 1 else 0) + length additionalWansIPv6;

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
      description = ''
        List of WAN interfaces to monitor for prioritized uplink failover.
        This module adjusts route metrics; it is not a generic ECMP or
        aggregate load-balancing surface.
      '';
    };

    ipv6SourceAddressAcknowledged = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Acknowledge that IPv6 multi-WAN source-address correctness is the
        operator's responsibility.

        When multiple WAN uplinks accept IPv6 router advertisements, failover
        can cause traffic to exit on a WAN whose prefix does not match the
        source address chosen by the client. Upstream ingress filtering
        (BCP38 / RFC 2827) will silently drop such packets.

        Safe mitigation options include:
        - NPTv6 (services.router-nptv6) to translate between a stable
          internal prefix and each WAN's delegated prefix
        - Source-based policy routing rules
        - Disabling IPv6 RA on all but one WAN

        Set this to true once you have addressed source-address correctness
        for your deployment.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          ipv6WanCount <= 1
          || nptv6Enabled
          || cfg.ipv6SourceAddressAcknowledged;
        message = ''
          router-mwan: Multiple WAN interfaces accept IPv6 router advertisements
          but no source-address mitigation is configured.

          IPv6 multi-WAN failover without source-address guardrails will cause
          silent packet drops when upstream providers use ingress filtering
          (BCP38 / RFC 2827). Traffic exiting on a WAN whose prefix does not
          match the client's source address will be dropped.

          To fix this, do one of:
          - Enable NPTv6 (services.router-nptv6.enable = true) for prefix translation
          - Configure source-based policy routing for each uplink prefix
          - Disable IPv6 RA on all but one WAN (ipv6AcceptRA = false)
          - Set services.router-mwan.ipv6SourceAddressAcknowledged = true
            if you have addressed this externally
        '';
      }
    ];
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
