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
in
{
  default-module-bundle-eval = eval.mkNixosEvalCheck "default-module-bundle" [
    self.nixosModules.default
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
      ];
    }
  ];
}
// vpnSmokeChecks
// interfaceFirewallInvariantChecks
// docExampleChecks
// lib.mapAttrs' (
  name: module:
  lib.nameValuePair "module-${name}-import-eval" (
    eval.mkNixosEvalCheck "module-${name}-import" [
      module
    ]
  )
) self.nixosModules
