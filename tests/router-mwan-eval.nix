{
  self,
  eval,
  ...
}:

{
  # Multi-WAN with multiple IPv6 WANs and no mitigation should fail.
  router-mwan-ipv6-source-address-unguarded-fails = eval.mkNixosEvalFailureCheck "router-mwan-ipv6-source-address-unguarded" [
    self.nixosModules.router-networking
    self.nixosModules.router-mwan
    self.nixosModules.router-nptv6
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          ipv6AcceptRA = true;
        };
        wans.secondary = {
          device = "eth1";
          ipv6AcceptRA = true;
        };
      };

      services.router-mwan = {
        enable = true;
        interfaces = [
          { interface = "eth0"; }
          { interface = "eth1"; }
        ];
      };
    }
  ];

  # Multi-WAN with NPTv6 enabled should pass.
  router-mwan-ipv6-with-nptv6-eval = eval.mkNixosEvalCheck "router-mwan-ipv6-with-nptv6" [
    self.nixosModules.router-networking
    self.nixosModules.router-firewall
    self.nixosModules.router-mwan
    self.nixosModules.router-nptv6
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          ipv6AcceptRA = true;
        };
        wans.secondary = {
          device = "eth1";
          ipv6AcceptRA = true;
        };
      };

      services.router-mwan = {
        enable = true;
        interfaces = [
          { interface = "eth0"; }
          { interface = "eth1"; }
        ];
      };

      services.router-nptv6 = {
        enable = true;
        rules = [
          {
            internalPrefix = "fd00:1::/64";
            externalInterface = "eth0";
            autoDetect = true;
          }
        ];
      };
    }
  ];

  # Multi-WAN with explicit acknowledgment should pass.
  router-mwan-ipv6-acknowledged-eval = eval.mkNixosEvalCheck "router-mwan-ipv6-acknowledged" [
    self.nixosModules.router-networking
    self.nixosModules.router-mwan
    self.nixosModules.router-nptv6
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          ipv6AcceptRA = true;
        };
        wans.secondary = {
          device = "eth1";
          ipv6AcceptRA = true;
        };
      };

      services.router-mwan = {
        enable = true;
        ipv6SourceAddressAcknowledged = true;
        interfaces = [
          { interface = "eth0"; }
          { interface = "eth1"; }
        ];
      };
    }
  ];

  # Multi-WAN with only one IPv6 WAN should pass without acknowledgment.
  router-mwan-single-ipv6-wan-eval = eval.mkNixosEvalCheck "router-mwan-single-ipv6-wan" [
    self.nixosModules.router-networking
    self.nixosModules.router-mwan
    self.nixosModules.router-nptv6
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          ipv6AcceptRA = true;
        };
        wans.secondary = {
          device = "eth1";
          ipv6AcceptRA = false;
        };
      };

      services.router-mwan = {
        enable = true;
        interfaces = [
          { interface = "eth0"; }
          { interface = "eth1"; }
        ];
      };
    }
  ];
}
