{
  self,
  lib,
  eval,
}:

{
  router-ha-ntp-boundary-docs-eval = eval.mkNixosEvalCheck "router-ha-ntp-boundary-docs" [
    self.nixosModules.router-ha
    self.nixosModules.router-ntp
    self.nixosModules.router-firewall
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
      };

      services.router-ntp = {
        enable = true;
        lanSubnets = [ "10.10.0.0/16" ];
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "ens17" ];
        lanInterfaces = [ "ens18" ];
      };
    }
    ({ config, ... }:
      let
        ownershipDoc = builtins.readFile ../docs/router-ha-ownership.md;
      in
      {
        assertions = [
          {
            assertion = config.services.chrony.enable;
            message = "router-ntp should still enable chrony under router-ha.";
          }
          {
            assertion = !(lib.strings.hasInfix "chrony" config.services.keepalived.vrrpInstances.main.extraConfig);
            message = "router-ha should not inject Chrony ownership hooks by default.";
          }
          {
            assertion = builtins.elem 123 (config.services.router-firewall.trustedUdpPorts or [ ]);
            message = "router-ntp should keep opening trusted UDP 123 even when router-ha is enabled.";
          }
          {
            assertion =
              lib.strings.hasInfix "typed `router-ha` adapter for NTP" ownershipDoc
              && lib.strings.hasInfix "Expected policy owner" ownershipDoc;
            message = "router-ha ownership docs should explicitly record the NTP non-support stance.";
          }
        ];
      })
  ];
}
