{ self }:

# Shared nodes for the two-router HA VM tests: a simulated ISP on vlan 1
# (DHCPv4 tied to the cloned MAC, DHCPv6 with prefix delegation, periodic
# RAs) and a router builder with WAN on vlan 1, LAN on vlan 2 (VIP
# 10.0.10.1) and management on vlan 3.
rec {
  clonedMac = "02:00:00:00:00:b0";

  mkRouter =
    {
      role,
      lanAddress,
      mgmtAddress,
      extraModule ? { },
    }:
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.router-networking
        self.nixosModules.router-ha
        extraModule
      ];

      virtualisation.vlans = [
        1
        2
        3
      ];

      networking.firewall.enable = false;

      services.router-networking = {
        enable = true;
        waitOnline = false;
        wan = {
          device = "eth1";
          mode = "dhcp";
        };
        routedInterfaces.lan = {
          device = "eth2";
          ipv4Address = lanAddress;
        };
      };

      systemd.network.networks."20-mgmt" = {
        matchConfig.Name = "eth3";
        address = [ mgmtAddress ];
        linkConfig.RequiredForOnline = "no";
      };

      # Test-only VRRP password; real deployments use a secret manager path.
      environment.etc."router-ha/vrrp-password".text = "vmtest1";

      services.router-ha = {
        enable = true;
        inherit role;
        vrrpPasswordFile = "/etc/router-ha/vrrp-password";
        virtualIp = "10.0.10.1/24";
        vrrpInterface = "eth2";
        # The LAN sends RAs (router-networking default); only the MASTER may.
        routerAdvertisements.mode = "vrrp-owner";
        wan = {
          enable = true;
          interface = "eth1";
          inherit clonedMac;
        };
      };

      # Debug logs show the RA/DHCPv6 exchange if wait_pd ever times out.
      systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";

      environment.systemPackages = [
        pkgs.jq
        pkgs.iproute2
      ];
    };

  isp = { pkgs, ... }: {
    virtualisation.vlans = [ 1 ];
    networking = {
      useNetworkd = true;
      firewall.enable = false;
    };
    systemd.network.networks."10-wan" = {
      matchConfig.Name = "eth1";
      address = [
        "198.51.100.1/24"
        "2001:db8:1::1/64"
      ];
    };
    # GOTCHA: networkd starts DHCPv6 only after an RA (WithoutRA=no). Send
    # frequent unsolicited RAs with the managed flag, like a real ISP, so a
    # newly promoted WAN never depends on one router solicitation getting
    # answered (that flaked under CI load).
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
    services.radvd = {
      enable = true;
      config = ''
        interface eth1 {
          AdvSendAdvert on;
          MinRtrAdvInterval 3;
          MaxRtrAdvInterval 4;
          AdvManagedFlag on;
          AdvOtherConfigFlag on;
        };
      '';
    };
    # The cloned MAC always gets the same address, like an ISP that ties the
    # lease to the CPE MAC.
    services.dnsmasq = {
      enable = true;
      settings = {
        interface = "eth1";
        bind-interfaces = true;
        port = 0;
        dhcp-range = [ "198.51.100.100,198.51.100.150,2m" ];
        dhcp-host = [ "${clonedMac},198.51.100.50" ];
        dhcp-authoritative = true;
      };
    };
    services.kea.dhcp6 = {
      enable = true;
      settings = {
        interfaces-config.interfaces = [ "eth1" ];
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp6.leases";
        };
        valid-lifetime = 600;
        preferred-lifetime = 300;
        subnet6 = [
          {
            id = 1;
            subnet = "2001:db8:1::/64";
            interface = "eth1";
            pools = [ { pool = "2001:db8:1::100-2001:db8:1::1ff"; } ];
            pd-pools = [
              {
                prefix = "2001:db8:100::";
                prefix-len = 40;
                delegated-len = 56;
              }
            ];
          }
        ];
      };
    };
  };
}
