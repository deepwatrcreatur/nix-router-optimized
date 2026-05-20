{
  self,
  lib,
  eval,
  ...
}:

{
  router-zones-lan-wan-eval = eval.mkNixosEvalCheck "router-zones-lan-wan" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };

      services.router-zones = {
        enable = true;
        zones = {
          wan.interfaces = [ "wan0" ];
          lan.interfaces = [ "lan0" ];
        };
        policies = [
          {
            fromZone = "lan";
            toZone = "wan";
            action = "accept";
          }
        ];
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''iifname { "lan0" } jump zone_lan_forward'' config.networking.nftables.ruleset;
          message = "router-zones should dispatch LAN traffic into the zone chain.";
        }
        {
          assertion = lib.hasInfix ''oifname { "wan0" } accept comment "router-zones lan->wan"'' config.networking.nftables.ruleset;
          message = "router-zones should render the explicit LAN-to-WAN policy.";
        }
      ];
    })
  ];

  router-zones-iot-isolation-eval = eval.mkNixosEvalCheck "router-zones-iot-isolation" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };

      services.router-zones = {
        enable = true;
        zones = {
          wan.interfaces = [ "wan0" ];
          lan.interfaces = [ "lan0" ];
          iot = {
            interfaces = [ "iot0" ];
            defaultForwardAction = "drop";
          };
        };
        policies = [
          {
            fromZone = "iot";
            toZone = "wan";
            action = "accept";
          }
          {
            fromZone = "iot";
            toZone = "lan";
            action = "drop";
          }
        ];
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''oifname { "wan0" } accept comment "router-zones iot->wan"'' config.networking.nftables.ruleset;
          message = "router-zones should allow explicit IoT-to-WAN policy.";
        }
        {
          assertion = lib.hasInfix ''oifname { "lan0" } drop comment "router-zones iot->lan"'' config.networking.nftables.ruleset;
          message = "router-zones should allow explicit IoT isolation policy.";
        }
        {
          assertion = lib.hasInfix ''drop comment "router-zones default for iot"'' config.networking.nftables.ruleset;
          message = "router-zones should honor the IoT default drop action.";
        }
      ];
    })
  ];

  router-zones-missing-from-zone-fails = eval.mkNixosEvalFailureCheck "router-zones-missing-from-zone" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };

      services.router-zones = {
        enable = true;
        zones.wan.interfaces = [ "wan0" ];
        policies = [
          {
            fromZone = "lan";
            toZone = "wan";
            action = "accept";
          }
        ];
      };
    }
  ];

  router-zones-missing-to-zone-fails = eval.mkNixosEvalFailureCheck "router-zones-missing-to-zone" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };

      services.router-zones = {
        enable = true;
        zones.lan.interfaces = [ "lan0" ];
        policies = [
          {
            fromZone = "lan";
            toZone = "wan";
            action = "accept";
          }
        ];
      };
    }
  ];

  router-zones-duplicate-interface-fails = eval.mkNixosEvalFailureCheck "router-zones-duplicate-interface" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };

      services.router-zones = {
        enable = true;
        zones = {
          lan.interfaces = [ "shared0" ];
          iot.interfaces = [ "shared0" ];
        };
      };
    }
  ];

  router-zones-empty-zones-fails = eval.mkNixosEvalFailureCheck "router-zones-empty-zones" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall.enable = true;
      services.router-zones = {
        enable = true;
        zones = { };
      };
    }
  ];

  router-zones-firewall-disabled-fails = eval.mkNixosEvalFailureCheck "router-zones-firewall-disabled" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall.enable = false;
      services.router-zones = {
        enable = true;
        zones.lan.interfaces = [ "lan0" ];
      };
    }
  ];

  router-zones-sanitization-collision-fails = eval.mkNixosEvalFailureCheck "router-zones-sanitization-collision" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall.enable = true;
      services.router-zones = {
        enable = true;
        zones = {
          "lan.0".interfaces = [ "eth1" ];
          "lan-0".interfaces = [ "eth2" ];
        };
      };
    }
  ];

  router-zones-sanitization-eval = eval.mkNixosEvalCheck "router-zones-sanitization" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
      };
      services.router-zones = {
        enable = true;
        zones = {
          wan.interfaces = [ "wan0" ];
          "lan.0".interfaces = [ "lan0" ];
        };
        policies = [
          {
            fromZone = "lan.0";
            toZone = "wan";
            action = "reject";
          }
        ];
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''chain zone_lan-0_forward'' config.networking.nftables.ruleset;
          message = "router-zones should sanitize special characters in chain definitions.";
        }
        {
          assertion = lib.hasInfix ''jump zone_lan-0_forward'' config.networking.nftables.ruleset;
          message = "router-zones should sanitize special characters in jump rules.";
        }
        {
          assertion = lib.hasInfix ''oifname { "wan0" } reject comment "router-zones lan.0->wan"'' config.networking.nftables.ruleset;
          message = "router-zones should render reject policy actions.";
        }
        {
          assertion = lib.hasInfix ''return comment "router-zones default for lan.0"'' config.networking.nftables.ruleset;
          message = "router-zones should preserve the default return action.";
        }
      ];
    })
  ];
}
