{
  self,
  lib,
  eval,
  ...
}:

let
  ipLib = import ../modules/lib/ip.nix { inherit lib; };
in
{
  # 1. Pure Nix IP CIDR utility tests
  router-ip-lib-eval = eval.mkNixosEvalCheck "router-ip-lib" [
    ({ ... }: {
      assertions = [
        # IPv4 Overlaps
        {
          assertion = ipLib.cidrsOverlap "10.0.0.0/24" "10.0.0.128/25";
          message = "10.0.0.0/24 must overlap with 10.0.0.128/25";
        }
        {
          assertion = !ipLib.cidrsOverlap "10.0.0.0/24" "10.0.1.0/24";
          message = "10.0.0.0/24 must not overlap with 10.0.1.0/24";
        }
        # IPv4 Containment
        {
          assertion = ipLib.cidrContains "10.0.0.0/16" "10.0.5.0/24";
          message = "10.0.0.0/16 must contain 10.0.5.0/24";
        }
        {
          assertion = !ipLib.cidrContains "10.0.5.0/24" "10.0.0.0/16";
          message = "10.0.5.0/24 must not contain 10.0.0.0/16";
        }
        {
          assertion = ipLib.cidrContainsIP "10.0.0.0/24" "10.0.0.50";
          message = "10.0.0.0/24 must contain 10.0.0.50";
        }
        {
          assertion = !ipLib.cidrContainsIP "10.0.0.0/24" "10.0.1.50";
          message = "10.0.0.0/24 must not contain 10.0.1.50";
        }
        # IPv6 Overlaps
        {
          assertion = ipLib.cidrsOverlap "fd42:100:1::/48" "fd42:100:1:2::/64";
          message = "fd42:100:1::/48 must overlap with fd42:100:1:2::/64";
        }
        {
          assertion = !ipLib.cidrsOverlap "fd42:100:1::/64" "fd42:100:2::/64";
          message = "fd42:100:1::/64 must not overlap with fd42:100:2::/64";
        }
        # IPv6 Containment
        {
          assertion = ipLib.cidrContains "fd42:100::/32" "fd42:100:1::/48";
          message = "fd42:100::/32 must contain fd42:100:1::/48";
        }
        {
          assertion = ipLib.cidrContainsIP "fd42:100:1::/64" "fd42:100:1::5";
          message = "fd42:100:1::/64 must contain fd42:100:1::5";
        }
        {
          assertion = !ipLib.cidrContainsIP "fd42:100:1::/64" "fd42:100:2::5";
          message = "fd42:100:1::/64 must not contain fd42:100:2::5";
        }
      ];
    })
  ];

  # 2. Positive check: Valid non-overlapping topology passes cleanly
  router-valid-topology-eval = eval.mkNixosEvalCheck "router-valid-topology" [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          mode = "static";
          ipv4Address = "203.0.113.2/24";
          gateway4 = "203.0.113.1";
        };
        routedInterfaces = {
          lan = {
            device = "eth1";
            ipv4Address = "10.10.10.1/24";
            mtu = 1500;
          };
          iot = {
            device = "eth1.20";
            parentDevice = "eth1";
            vlanId = 20;
            ipv4Address = "10.10.20.1/24";
            mtu = 1500;
          };
        };
      };
      services.router-dhcp = {
        enable = true;
        interfaces.lan = {
          enable = true;
          poolOffset = 50;
          poolSize = 100;
        };
      };
    }
  ];

  # 3. Negative test: Overlapping routed subnets fails evaluation
  router-overlapping-subnets-fails-eval = eval.mkNixosEvalFailureCheck "router-overlapping-subnets" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        routedInterfaces = {
          lan = {
            device = "eth1";
            ipv4Address = "10.10.0.1/16";
          };
          guest = {
            device = "eth2";
            ipv4Address = "10.10.10.1/24";
          };
        };
      };
    }
  ];

  # 4. Negative test: Overlapping routed and static WAN subnets fails evaluation
  router-overlapping-wan-lan-fails-eval = eval.mkNixosEvalFailureCheck "router-overlapping-wan-lan" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        wan = {
          device = "eth0";
          mode = "static";
          ipv4Address = "192.168.1.5/24";
          gateway4 = "192.168.1.1";
        };
        routedInterfaces = {
          lan = {
            device = "eth1";
            ipv4Address = "192.168.1.1/24";
          };
        };
      };
    }
  ];

  # 5. Negative test: Out-of-bounds DHCP pool fails evaluation
  router-dhcp-pool-exceeds-subnet-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-pool-exceeds-subnet" [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    {
      services.router-networking = {
        enable = true;
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.10.1/29"; # /29 has only 8 addresses total (1-6 usable)
        };
      };
      services.router-dhcp = {
        enable = true;
        interfaces.lan = {
          enable = true;
          poolOffset = 2;
          poolSize = 50; # 50 exceeds /29 subnet
        };
      };
    }
  ];

  # 6. Negative test: VLAN MTU exceeding parent device MTU fails evaluation
  router-vlan-mtu-exceeds-parent-fails-eval = eval.mkNixosEvalFailureCheck "router-vlan-mtu-exceeds-parent" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        routedInterfaces = {
          parent = {
            device = "eth1";
            ipv4Address = "10.10.10.1/24";
            mtu = 1500;
          };
          childVlan = {
            device = "eth1.10";
            parentDevice = "eth1";
            vlanId = 10;
            ipv4Address = "10.10.20.1/24";
            mtu = 9000; # 9000 > 1500
          };
        };
      };
    }
  ];

  # 7. Negative test: VRRP VIP colliding with static interface IP fails evaluation
  router-vrrp-vip-collision-fails-eval = eval.mkNixosEvalFailureCheck "router-vrrp-vip-collision" [
    self.nixosModules.router-networking
    self.nixosModules.router-ha
    {
      services.router-networking = {
        enable = true;
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.10.1/24";
        };
      };
      services.router-ha = {
        enable = true;
        role = "master";
        vrrpInterface = "eth1";
        virtualIp = "10.10.10.1/24"; # Collides with static IP 10.10.10.1
      };
    }
  ];
}
