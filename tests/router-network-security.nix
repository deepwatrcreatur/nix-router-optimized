{
  self,
  lib,
  eval,
  ...
}:

let
  firewallBase = {
    services.router-firewall = {
      enable = true;
      wanInterfaces = [ "wan0" ];
      lanInterfaces = [ "lan0" ];
    };
  };

  routerNetworkingBase = {
    services.router-networking.routedInterfaces.lan = {
      device = "lan0";
      role = "lan";
      ipv4Address = "10.10.10.1/24";
    };
  };
in
{
  router-network-security-suricata-eval = eval.mkNixosEvalCheck "router-network-security-suricata" [
    self.nixosModules.router-firewall
    self.nixosModules.router-networking
    self.nixosModules.router-network-security
    firewallBase
    routerNetworkingBase
    {
      services.router-network-security = {
        enable = true;
        suricata.enable = true;
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.suricata.enable;
          message = "router-network-security should enable upstream Suricata when requested.";
        }
        {
          assertion = (builtins.head config.services.suricata.settings.pcap).interface == "wan0";
          message = "router-network-security should derive Suricata capture interfaces from router-firewall.";
        }
        {
          assertion = config.services.suricata.settings.vars.address-groups.HOME_NET == [ "10.10.10.1/24" ];
          message = "router-network-security should derive HOME_NET from router-networking routed IPv4 CIDRs.";
        }
        {
          assertion = config.systemd.services.suricata-update.wantedBy == [ ];
          message = "router-network-security should not make suricata-update an activation-time requirement by default.";
        }
        {
          assertion = config.systemd.timers.suricata-update.wantedBy == [ "timers.target" ];
          message = "router-network-security should keep Suricata rule updates timer-driven when activation updates are disabled.";
        }
        {
          assertion = config.systemd.services ? router-suricata-seed-rules;
          message = "router-network-security should seed packaged Suricata rules before update/start.";
        }
        {
          assertion = lib.hasInfix "router-suricata-seed-rules"
            config.systemd.services.router-suricata-seed-rules.serviceConfig.ExecStart;
          message = "router-network-security should install a dedicated seed-rules helper script.";
        }
        {
          assertion = config.systemd.services.router-suricata-seed-rules.requiredBy == [
            "suricata.service"
            "suricata-update.service"
          ];
          message = "router-network-security should seed Suricata support files into the runtime rule path.";
        }
      ];
    })
  ];

  router-network-security-suricata-activation-update-eval = eval.mkNixosEvalCheck "router-network-security-suricata-activation-update" [
    self.nixosModules.router-firewall
    self.nixosModules.router-networking
    self.nixosModules.router-network-security
    firewallBase
    routerNetworkingBase
    {
      services.router-network-security = {
        enable = true;
        suricata = {
          enable = true;
          startUpdateServiceOnActivation = true;
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.systemd.services.suricata-update.wantedBy == [ "multi-user.target" ];
          message = "router-network-security should preserve activation-time Suricata updates when explicitly requested.";
        }
        {
          assertion = config.systemd.timers.suricata-update.wantedBy == [ "timers.target" ];
          message = "router-network-security should keep the Suricata update timer enabled even when activation-time updates are requested.";
        }
      ];
    })
  ];

  router-network-security-snort-eval = eval.mkNixosEvalCheck "router-network-security-snort" [
    self.nixosModules.router-firewall
    self.nixosModules.router-networking
    self.nixosModules.router-network-security
    firewallBase
    routerNetworkingBase
    {
      services.router-network-security = {
        enable = true;
        snort = {
          enable = true;
          profile = "security";
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.systemd.services ? router-snort;
          message = "router-network-security should expose a Snort systemd service when requested.";
        }
        {
          assertion = lib.hasInfix "/bin/snort -c " config.systemd.services.router-snort.serviceConfig.ExecStart;
          message = "router-network-security should launch the packaged Snort binary.";
        }
        {
          assertion = lib.hasInfix "--daq-mode passive -i wan0 -i lan0" config.systemd.services.router-snort.serviceConfig.ExecStart;
          message = "router-network-security should pass derived interfaces into Snort.";
        }
        {
          assertion = lib.hasInfix "--lua 'HOME_NET = '\\''10.10.10.1/24'\\'''"
            config.systemd.services.router-snort.serviceConfig.ExecStart;
          message = "router-network-security should inject the derived HOME_NET into Snort.";
        }
      ];
    })
  ];

  router-network-security-zeek-eval = eval.mkNixosEvalCheck "router-network-security-zeek" [
    self.nixosModules.router-firewall
    self.nixosModules.router-network-security
    firewallBase
    {
      services.router-network-security = {
        enable = true;
        zeek.enable = true;
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.systemd.services ? router-zeek-wan0;
          message = "router-network-security should create a Zeek service for each capture interface.";
        }
        {
          assertion = lib.hasInfix "/bin/zeek -i wan0" config.systemd.services.router-zeek-wan0.serviceConfig.ExecStart;
          message = "router-network-security should launch Zeek with the interface-specific command line.";
        }
        {
          assertion = lib.hasInfix "local" config.systemd.services.router-zeek-lan0.serviceConfig.ExecStart;
          message = "router-network-security should load the default local Zeek policy script.";
        }
      ];
    })
  ];

  router-network-security-no-engine-fails-eval = eval.mkNixosEvalFailureCheck "router-network-security-no-engine-fails" [
    self.nixosModules.router-firewall
    self.nixosModules.router-network-security
    firewallBase
    {
      services.router-network-security.enable = true;
    }
  ];
}
