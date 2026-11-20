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
        vrrpPasswordFile = "/run/keys/vrrp-password";
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

  router-ha-preempt-delay-eval = eval.mkNixosEvalCheck "router-ha-preempt-delay" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
        priority = 110;
        preemptDelay = 300;
      };
    }
    ({ config, ... }:
      let
        instance = config.services.keepalived.vrrpInstances.main;
      in
      {
        assertions = [
          {
            assertion = instance.state == "BACKUP";
            message = "router-ha with preemptDelay must start as BACKUP even for role = master (keepalived ignores preempt_delay on MASTER).";
          }
          {
            assertion = lib.strings.hasInfix "preempt_delay 300" instance.extraConfig;
            message = "router-ha should render preempt_delay from preemptDelay.";
          }
        ];
      })
  ];

  router-ha-preempt-default-eval = eval.mkNixosEvalCheck "router-ha-preempt-default" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
      };
    }
    ({ config, ... }:
      let
        instance = config.services.keepalived.vrrpInstances.main;
      in
      {
        assertions = [
          {
            assertion = instance.state == "MASTER" && !(lib.strings.hasInfix "preempt_delay" instance.extraConfig);
            message = "router-ha without preemptDelay must keep the role-based MASTER start and no preempt_delay (backwards compatible).";
          }
        ];
      })
  ];
}
