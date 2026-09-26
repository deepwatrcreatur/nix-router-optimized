{
  self,
  lib,
  eval,
  ...
}:

{
  router-optimizations-profile-generic-eval = eval.mkNixosEvalCheck "router-optimizations-profile-generic" [
    self.nixosModules.router-optimizations
    {
      services.router-optimizations = {
        enable = true;
        profile = "generic";
        interfaces = {
          wan = {
            device = "eth0";
            role = "wan";
            label = "WAN";
            bandwidth = "1Gbit";
          };
          lan = {
            device = "eth1";
            role = "lan";
            label = "LAN";
          };
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.router-optimizations.profile == "generic";
          message = "profile should be generic";
        }
        {
          assertion = config.systemd.services.router-hardware-offload.enable or true;
          message = "router-hardware-offload service should be enabled";
        }
        {
          assertion = config.boot.kernel.sysctl."net.ipv4.ip_forward" == 1;
          message = "ip_forward should be enabled";
        }
      ];
    })
  ];

  router-optimizations-profile-virtio-eval = eval.mkNixosEvalCheck "router-optimizations-profile-virtio" [
    self.nixosModules.router-optimizations
    {
      services.router-optimizations = {
        enable = true;
        profile = "virtio-vm";
        interfaces = {
          wan = {
            device = "vtnet0";
            role = "wan";
            label = "WAN";
          };
          lan = {
            device = "vtnet1";
            role = "lan";
            label = "LAN";
            offloadProfile = "generic";
          };
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.router-optimizations.profile == "virtio-vm";
          message = "profile should be virtio-vm";
        }
        {
          assertion = config.services.router-optimizations.interfaces.lan.offloadProfile == "generic";
          message = "per-interface offloadProfile should be generic";
        }
      ];
    })
  ];

  router-optimizations-profile-realtek-eval = eval.mkNixosEvalCheck "router-optimizations-profile-realtek" [
    self.nixosModules.router-optimizations
    {
      services.router-optimizations = {
        enable = true;
        profile = "realtek-baremetal";
        interfaces = {
          wan = {
            device = "re0";
            role = "wan";
            label = "WAN";
          };
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.router-optimizations.profile == "realtek-baremetal";
          message = "profile should be realtek-baremetal";
        }
      ];
    })
  ];

  router-optimizations-profile-intel-eval = eval.mkNixosEvalCheck "router-optimizations-profile-intel" [
    self.nixosModules.router-optimizations
    {
      services.router-optimizations = {
        enable = true;
        profile = "intel-baremetal";
        interfaces = {
          wan = {
            device = "igb0";
            role = "wan";
            label = "WAN";
          };
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.router-optimizations.profile == "intel-baremetal";
          message = "profile should be intel-baremetal";
        }
      ];
    })
  ];
}
