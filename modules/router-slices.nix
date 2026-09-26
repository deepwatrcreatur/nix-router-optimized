{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.router-slices;
in
{
  options.services.router-slices = {
    enable = mkEnableOption "systemd resource slice isolation for router processes";

    core = {
      oomScoreAdjust = mkOption {
        type = types.int;
        default = -900;
        description = "OOMScoreAdjust for critical routing processes (lower = protected from OOM).";
      };

      cpuWeight = mkOption {
        type = types.int;
        default = 1000;
        description = "CPUWeight for router-core.slice relative to other slices (1-10000).";
      };
    };

    observability = {
      memoryMax = mkOption {
        type = types.str;
        default = "256M";
        description = "Absolute maximum memory limit for telemetry and logging daemons.";
      };

      cpuQuota = mkOption {
        type = types.str;
        default = "30%";
        description = "Maximum CPU quota allocation for observability services.";
      };
    };

    applications = {
      memoryMax = mkOption {
        type = types.str;
        default = "512M";
        description = "Absolute maximum memory limit for auxiliary applications.";
      };

      cpuQuota = mkOption {
        type = types.str;
        default = "50%";
        description = "Maximum CPU quota allocation for application services.";
      };
    };
  };

  config = mkIf cfg.enable {
    # ── Define Slices ──────────────────────────────────────────────────────────

    systemd.slices."router-core" = {
      description = "Core router control plane and packet forwarding daemons";
      sliceConfig = {
        OOMScoreAdjust = cfg.core.oomScoreAdjust;
        CPUWeight = cfg.core.cpuWeight;
      };
    };

    systemd.slices."router-observability" = {
      description = "Router telemetry, packet logging, and monitoring daemons";
      sliceConfig = {
        MemoryMax = cfg.observability.memoryMax;
        CPUQuota = cfg.observability.cpuQuota;
      };
    };

    systemd.slices."router-applications" = {
      description = "Auxiliary router applications, web reverse proxies, and overlays";
      sliceConfig = {
        MemoryMax = cfg.applications.memoryMax;
        CPUQuota = cfg.applications.cpuQuota;
      };
    };

    # ── Assign Services to Slices ─────────────────────────────────────────────

    systemd.services = {
      # Router Core Slice
      systemd-networkd.serviceConfig.Slice = "router-core.slice";
      nftables.serviceConfig.Slice = "router-core.slice";
      kea-dhcp4-server.serviceConfig.Slice = "router-core.slice";
      unbound.serviceConfig.Slice = "router-core.slice";
      keepalived.serviceConfig.Slice = "router-core.slice";

      # Observability Slice
      ulogd.serviceConfig.Slice = "router-observability.slice";
      netdata.serviceConfig.Slice = "router-observability.slice";
      ntopng.serviceConfig.Slice = "router-observability.slice";

      # Applications Slice
      caddy.serviceConfig.Slice = "router-applications.slice";
      tailscaled.serviceConfig.Slice = "router-applications.slice";
    };
  };
}
