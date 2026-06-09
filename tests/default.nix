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
    inherit self lib eval;
  };

  routerNdppdChecks = import ./router-ndppd.nix {
    inherit self lib eval;
  };

  routerDashboardServiceControlChecks = import ./router-dashboard-service-control.nix {
    inherit self eval lib pkgs;
  };
in
{
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
// keaChecks
// routerDashboardInventoryChecks
// routerDashboardFirewallChecks
// routerDashboardServiceControlChecks
// routerSecurityHardeningChecks
// routerZonesChecks
// routerClatObservabilityChecks
// routerDhcpOption108BoundaryChecks
// routerMwanChecks
// routerHaBoundaryChecks
// routerNdppdChecks
// lib.mapAttrs' (
  name: module:
  lib.nameValuePair "module-${name}-import-eval" (
    eval.mkNixosEvalCheck "module-${name}-import" [
      module
    ]
  )
) self.nixosModules
