{
  self,
  lib,
  pkgs,
}:

# A branch router relays DHCPv4 for one routed segment (office, vlan 2) to a
# central Kea server (vlan 1) while its own Kea serves another segment (lan,
# vlan 3), so the networkd relay and Kea share UDP 67 on one host. The central
# server only hands out addresses to requests carrying the expected option 82
# (circuit ID and remote ID), so a lease proves the relay added them.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  dhcpClient = vlan: {
    virtualisation.vlans = [ vlan ];
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.networks."10-lan" = {
      matchConfig.Name = "eth1";
      networkConfig.DHCP = "ipv4";
    };
  };
in
mkRouterTest {
  name = "router-dhcp-relay";

  nodes = {
    server = {
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks."10-core" = {
        matchConfig.Name = "eth1";
        address = [ "10.0.1.2/24" ];
        # Replies go to the relay's address on the office segment (giaddr).
        routes = [
          {
            Destination = "10.20.0.0/24";
            Gateway = "10.0.1.1";
          }
        ];
      };
      services.kea.dhcp4 = {
        enable = true;
        settings = {
          interfaces-config.interfaces = [ "eth1" ];
          lease-database = {
            type = "memfile";
            persist = true;
            name = "/var/lib/kea/dhcp4.leases";
          };
          valid-lifetime = 600;
          # Keeps the relay agent info (option 82) with each lease.
          store-extended-info = true;
          client-classes = [
            {
              name = "office-relay";
              test = "relay4[1].hex == 'eth2' and relay4[2].hex == 'branch-router'";
            }
          ];
          subnet4 = [
            {
              id = 20;
              subnet = "10.20.0.0/24";
              pools = [
                {
                  pool = "10.20.0.100 - 10.20.0.199";
                  client-classes = [ "office-relay" ];
                }
              ];
              option-data = [
                {
                  name = "routers";
                  data = "10.20.0.1";
                }
              ];
            }
          ];
        };
      };
    };

    relay = {
      imports = [
        self.nixosModules.router-networking
        self.nixosModules.router-firewall
        self.nixosModules.router-kea
        self.nixosModules.router-dhcp-relay
      ];

      virtualisation.vlans = [
        1
        2
        3
      ];

      services.router-networking = {
        enable = true;
        waitOnline = false;
        wan = {
          device = "eth1";
          mode = "static";
          ipv4Address = "10.0.1.1/24";
          gateway4 = "10.0.1.2";
        };
        routedInterfaces = {
          office = {
            device = "eth2";
            ipv4Address = "10.20.0.1/24";
            ipv6SendRA = false;
          };
          lan = {
            device = "eth3";
            ipv4Address = "10.30.0.1/24";
            ipv6SendRA = false;
          };
        };
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth1" ];
        lanInterfaces = [
          "eth2"
          "eth3"
        ];
      };

      services.router-dhcp-relay = {
        enable = true;
        interfaces.office = {
          server = "10.0.1.2";
          remoteId = "branch-router";
        };
      };

      # Auto-detects lan-role segments; office is relayed, so only eth3.
      services.router-kea = {
        enable = true;
        exporter.enable = false;
        dhcp4 = {
          subnet = "10.30.0.0/24";
          gatewayAddress = "10.30.0.1";
          poolRanges = [
            {
              start = "10.30.0.100";
              end = "10.30.0.199";
            }
          ];
        };
      };
    };

    office = dhcpClient 2;
    lan = dhcpClient 3;
  };

  testScript = ''
    start_all()
    server.wait_for_unit("kea-dhcp4-server.service")
    relay.wait_for_unit("kea-dhcp4-server.service")
    relay.wait_for_unit("systemd-networkd.service")

    with subtest("Kea on the relay serves only the local segment"):
        import json, re
        exec_start = relay.succeed("systemctl show -p ExecStart --value kea-dhcp4-server.service")
        m = re.search(r"-c (\S+)", exec_start)
        assert m, f"no -c in {exec_start}"
        # nixpkgs passes it relative to / (e.g. etc/kea/dhcp4-server.conf).
        conf = "/" + m.group(1).lstrip("/")
        kea_ifaces = json.loads(relay.succeed(f"cat {conf}"))["Dhcp4"]["interfaces-config"]["interfaces"]
        assert kea_ifaces == ["eth3"], f"relay Kea listens on {kea_ifaces}"

    with subtest("office client gets a central lease through the relay with option 82"):
        office.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 10.20.0.1[0-9][0-9]/24'", timeout=90)
        addr = office.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}'").strip()
        print(f"office client: {addr}")
        server.wait_until_succeeds(f"grep -q '{addr.split('/')[0]}' /var/lib/kea/dhcp4.leases", timeout=30)
        lease = server.succeed(f"grep '{addr.split('/')[0]}' /var/lib/kea/dhcp4.leases").lower()
        # Circuit ID "eth2" and remote ID "branch-router" as hex suboptions.
        assert "657468" + "32" in lease and "6272616e63682d726f75746572" in lease, f"no option 82 in lease: {lease}"
        office.succeed("ping -c1 -W2 10.20.0.1")

    with subtest("lan client gets a lease from the relay's own Kea"):
        lan.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 10.30.0.1[0-9][0-9]/24'", timeout=90)
        server.fail("grep -q '10.30.0.' /var/lib/kea/dhcp4.leases")
  '';
}
