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
          assertion = config.services.suricata.settings.vars.address-groups.EXTERNAL_NET == "!$HOME_NET";
          message = "router-network-security should define EXTERNAL_NET in terms of the derived HOME_NET so the default Suricata ruleset parses cleanly.";
        }
      ];
    })
  ];

  router-network-security-suricata-evebox-eval = eval.mkNixosEvalCheck "router-network-security-suricata-evebox" [
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
          evebox.enable = true;
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.systemd.services ? router-evebox;
          message = "router-network-security should expose an EveBox service when requested.";
        }
        {
          assertion = lib.hasInfix "/bin/evebox --data-directory /var/lib/evebox server --sqlite --no-tls --host 127.0.0.1 --port 5636 --input /var/log/suricata/eve.json --end --no-auth"
            config.systemd.services.router-evebox.serviceConfig.ExecStart;
          message = "router-network-security should launch EveBox against the local Suricata eve.json tail.";
        }
        {
          assertion = config.systemd.services.router-evebox.serviceConfig.ReadOnlyPaths == [ "/var/log/suricata" ];
          message = "router-network-security should allow EveBox to read the configured Suricata EVE directory so log rotation does not break access.";
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

  router-network-security-suricata-evebox-without-suricata-fails-eval = eval.mkNixosEvalFailureCheck "router-network-security-suricata-evebox-without-suricata" [
    self.nixosModules.router-firewall
    self.nixosModules.router-network-security
    firewallBase
    {
      services.router-network-security = {
        enable = true;
        suricata.evebox.enable = true;
      };
    }
  ];
}
