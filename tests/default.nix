{
  self,
  lib,
  pkgs,
  nixpkgs,
  system,
}:

let
  eval = import ./nixos-eval.nix {
    inherit lib pkgs nixpkgs system;
  };

  exportedModuleNames = builtins.attrNames self.nixosModules;

  vpnSmokeChecks = import ./vpn-smoke.nix {
    inherit self lib eval;
  };

  proFeaturesSmokeChecks = import ./pro-features-smoke.nix {
    inherit self lib eval;
  };

  interfaceFirewallInvariantChecks = import ./interface-firewall-invariants.nix {
    inherit self lib eval;
  };

  docExampleChecks = import ./doc-examples.nix {
    inherit
      self
      lib
      pkgs
      nixpkgs
      system
      ;
  };

  nptv6Checks = import ./router-nptv6.nix {
    inherit self lib eval;
  };

  pvdChecks = import ./router-pvd.nix {
    inherit self lib eval;
  };

  routerIpv6RaControlChecks = import ./router-ipv6-ra-control.nix {
    inherit self lib eval;
  };

  keaChecks = import ./router-kea-eval.nix {
    inherit self eval;
  };

  routerSecurityHardeningChecks = import ./router-security-hardened.nix {
    inherit self lib eval;
  };

  routerZonesChecks = import ./router-zones.nix {
    inherit self lib eval;
  };

  routerDashboardInventoryChecks = import ./router-dashboard-inventory.nix {
    inherit self eval lib pkgs;
  };

  routerDashboardFirewallChecks = import ./router-dashboard-firewall.nix {
    inherit self eval lib;
  };

  routerClatObservabilityChecks = import ./router-clat-observability.nix {
    inherit self lib eval;
  };

  routerDhcpOption108BoundaryChecks = import ./router-dhcp-option108-boundary.nix {
    inherit self lib eval;
  };

  routerMwanChecks = import ./router-mwan-eval.nix {
    inherit self eval;
  };

  routerHaBoundaryChecks = import ./router-ha-boundaries.nix {
    inherit self lib pkgs nixpkgs system eval;
  };

  routerHaOwnershipChecks = import ./router-ha-ownership.nix {
    inherit self lib eval;
  };

  routerDhcpRelayChecks = import ./router-dhcp-relay.nix {
    inherit self lib eval;
  };

  routerIpsecChecks = import ./router-ipsec.nix {
    inherit self lib eval;
  };

  routerTechnitiumZoneReplicationChecks = import ./router-technitium-zone-replication.nix {
    inherit self lib eval;
  };

  routerHomelabLinkChecks = import ./router-homelab-links.nix {
    inherit self lib eval;
  };

  routerHaVrrpAuthChecks = import ./router-ha-vrrp-auth.nix {
    inherit self lib pkgs nixpkgs system eval;
  };

  routerAlertingChecks = import ./router-alerting.nix {
    inherit self lib pkgs nixpkgs system eval;
  };

  routerNdppdChecks = import ./router-ndppd.nix {
    inherit self lib eval;
  };

  routerDashboardServiceControlChecks = import ./router-dashboard-service-control.nix {
    inherit self eval lib pkgs;
  };

  routerNetworkSecurityChecks = import ./router-network-security.nix {
    inherit self lib eval pkgs;
  };

  routerPangolinChecks = import ./router-pangolin.nix {
    inherit self eval;
  };

  routerHaLabChecks = import ./router-ha-lab.nix {
    inherit self lib eval pkgs;
  };

  routerOptimizationsChecks = import ./router-optimizations.nix {
    inherit self lib eval;
  };

  routerAssertionsChecks = import ./router-assertions.nix {
    inherit self lib eval;
  };

  routerSlicesChecks = import ./router-slices.nix {
    inherit self lib eval;
  };

  vmSmokeCheck = import ./vm/router-basic-smoke.nix {
    inherit self lib pkgs;
  };

  vmKeaHaCheck = import ./vm/router-kea-ha.nix {
    inherit self lib pkgs;
  };

  vmHaWanFailoverCheck = import ./vm/router-ha-wan-failover.nix {
    inherit self lib pkgs;
  };

  vmHaWanHealthCheck = import ./vm/router-ha-wan-health.nix {
    inherit self lib pkgs;
  };

  vmHwSensorsCheck = import ./vm/router-hw-sensors.nix {
    inherit self lib pkgs;
  };

  vmRouterApplyCheck = import ./vm/router-apply.nix {
    inherit self lib pkgs;
  };

  vmHaPairCheck = import ./vm/router-ha-pair.nix {
    inherit self lib pkgs;
  };

  vmTechnitiumZoneHaCheck = import ./vm/router-technitium-zone-ha.nix {
    inherit self lib pkgs;
  };

  vmDhcpRelayCheck = import ./vm/router-dhcp-relay.nix {
    inherit self lib pkgs;
  };

  vmIpsecCheck = import ./vm/router-ipsec.nix {
    inherit self lib pkgs;
  };
in
{
  vm-smoke = vmSmokeCheck;
  vm-router-kea-ha = vmKeaHaCheck;
  vm-router-ha-wan-failover = vmHaWanFailoverCheck;
  vm-router-ha-pair = vmHaPairCheck;
  vm-router-apply = vmRouterApplyCheck;
  vm-router-hw-sensors = vmHwSensorsCheck;
  vm-router-ha-wan-health = vmHaWanHealthCheck;
  vm-router-technitium-zone-ha = vmTechnitiumZoneHaCheck;
  vm-router-dhcp-relay = vmDhcpRelayCheck;
  vm-router-ipsec = vmIpsecCheck;

  router-monitoring-hardware-sensors-eval = eval.mkNixosEvalCheck "router-monitoring-hardware-sensors" [
    self.nixosModules.monitoring
    {
      router.monitoring = {
        enable = true;
        hardwareSensors.enable = true;
      };
    }
    ({ config, ... }:
      let
        node = config.services.prometheus.exporters.node;
        dash = builtins.fromJSON config.environment.etc."grafana-dashboards/router-hardware.json".text;
        exprs = map (p: (builtins.head (p.targets or [ { expr = ""; } ])).expr) dash.dashboard.panels;
      in
      {
        assertions = [
          {
            assertion = builtins.elem "textfile" node.enabledCollectors
              && builtins.elem "--collector.textfile.directory=/run/router-hw-sensors" node.extraFlags;
            message = "hardwareSensors must enable node_exporter's textfile collector on /run/router-hw-sensors.";
          }
          {
            assertion = config.systemd.timers ? router-hw-sensors
              && lib.hasInfix "router-hw-sensors /run/router-hw-sensors" config.systemd.services.router-hw-sensors.serviceConfig.ExecStart;
            message = "hardwareSensors must run router-hw-sensors on a timer into the textfile directory.";
          }
          {
            assertion = dash.dashboard.uid == "router-hardware"
              && builtins.elem "router_nic_asic_temperature_celsius" exprs
              && builtins.elem "router_sfp_temperature_celsius" exprs
              && builtins.elem "node_hwmon_temp_celsius" exprs;
            message = "The Router Hardware dashboard (uid router-hardware) must graph hwmon, NIC ASIC and SFP temperatures.";
          }
        ];
      })
  ];

  router-monitoring-hardware-sensors-default-off-eval = eval.mkNixosEvalCheck "router-monitoring-hardware-sensors-default-off" [
    self.nixosModules.monitoring
    { router.monitoring.enable = true; }
    ({ config, ... }: {
      assertions = [
        {
          assertion = !(config.systemd.timers ? router-hw-sensors)
            && !(builtins.elem "textfile" config.services.prometheus.exporters.node.enabledCollectors);
          message = "router-hw-sensors must stay off unless router.monitoring.hardwareSensors.enable is set.";
        }
      ];
    })
  ];

  default-module-bundle-eval = eval.mkNixosEvalCheck "default-module-bundle" [
    self.nixosModules.default
  ];

  router-zones-requires-router-firewall-fails-eval = eval.mkNixosEvalFailureCheck "router-zones-requires-router-firewall" [
    self.nixosModules.router-zones
    {
      services.router-zones = {
        enable = true;
        zones.lan.interfaces = [ "eth1" ];
      };
    }
  ];

  exported-module-list-eval = eval.mkNixosEvalCheck "exported-module-list" [
    {
      assertions = [
        {
          assertion = builtins.elem "default" exportedModuleNames;
          message = "nixosModules.default must stay exported.";
        }
        {
          assertion = builtins.elem "router-ddns" exportedModuleNames;
          message = "nixosModules.router-ddns must stay exported.";
        }
        {
          assertion = builtins.elem "router-ndp-proxy" exportedModuleNames;
          message = "nixosModules.router-ndp-proxy must stay exported.";
        }
        {
          assertion = builtins.elem "router-network-security" exportedModuleNames;
          message = "nixosModules.router-network-security must stay exported.";
        }
        {
          assertion = builtins.elem "router-slices" exportedModuleNames;
          message = "nixosModules.router-slices must stay exported.";
        }
      ];
    }
  ];
}
// vpnSmokeChecks
// proFeaturesSmokeChecks
// interfaceFirewallInvariantChecks
// docExampleChecks
// nptv6Checks
// pvdChecks
// routerIpv6RaControlChecks
// keaChecks
// routerDashboardInventoryChecks
// routerDashboardFirewallChecks
// routerDashboardServiceControlChecks
// routerNetworkSecurityChecks
// routerPangolinChecks
// routerSecurityHardeningChecks
// routerZonesChecks
// routerClatObservabilityChecks
// routerDhcpOption108BoundaryChecks
// routerMwanChecks
// routerHaBoundaryChecks
// routerHaOwnershipChecks
// routerHaVrrpAuthChecks
// routerAlertingChecks
// routerHomelabLinkChecks
// routerTechnitiumZoneReplicationChecks
// routerDhcpRelayChecks
// routerIpsecChecks
// routerHaLabChecks
// routerNdppdChecks
// routerOptimizationsChecks
// routerAssertionsChecks
// routerSlicesChecks
// lib.mapAttrs' (
  name: module:
  lib.nameValuePair "module-${name}-import-eval" (
    eval.mkNixosEvalCheck "module-${name}-import" [
      module
    ]
  )
) self.nixosModules
