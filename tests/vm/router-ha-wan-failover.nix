{
  self,
  lib,
  pkgs,
}:

# Two routers share a WAN segment (vlan 1), a LAN (vlan 2) and a management
# segment (vlan 3). VRRP moves the LAN VIP and WAN ownership between them.
# The test proves that promotion and demotion touch only the WAN link: no
# carrier or static-address change on LAN or management, and no
# systemd-networkd restart.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  clonedMac = "02:00:00:00:00:b0";

  mkRouter =
    {
      role,
      lanAddress,
      mgmtAddress,
    }:
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.router-networking
        self.nixosModules.router-ha
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
        wan = {
          enable = true;
          interface = "eth1";
          inherit clonedMac;
        };
      };

      environment.systemPackages = [
        pkgs.jq
        pkgs.iproute2
      ];
    };
in
mkRouterTest {
  name = "router-ha-wan-failover";

  nodes = {
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
        # GOTCHA: networkd starts DHCPv6 only after an RA (WithoutRA=no), so
        # the simulated ISP advertises the managed flag like a real one.
        networkConfig.IPv6SendRA = true;
        ipv6SendRAConfig = {
          Managed = true;
          OtherInformation = true;
        };
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

    router1 = mkRouter {
      role = "master";
      lanAddress = "10.0.10.2/24";
      mgmtAddress = "192.168.100.2/24";
    };

    router2 = mkRouter {
      role = "backup";
      lanAddress = "10.0.10.3/24";
      mgmtAddress = "192.168.100.3/24";
    };

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 2 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-lan" = {
        matchConfig.Name = "eth1";
        address = [ "10.0.10.100/24" ];
      };
    };
  };

  testScript = ''
    routers = [router1, router2]
    LAN_OK_ADDR = "10.0.10.1"  # the VIP is the only LAN address allowed to move

    def wan_up(r):
        return "UP" in r.succeed("ip -o link show dev eth1").split(">")[0]

    def wait_role(r, role):
        r.wait_until_succeeds(f"grep -qx {role} /run/router-ha/role", timeout=60)

    def wait_wan_lease(r):
        r.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        r.succeed("ip link show dev eth1 | grep -q 'link/ether ${clonedMac}'")

    def wait_pd(r):
        try:
            r.wait_until_succeeds(
                "networkctl status --json=short eth1"
                " | jq -e '[.DHCPv6Client.Prefixes // [] | .[]] | length > 0'",
                timeout=90,
            )
        except Exception:
            print(r.succeed("networkctl status eth1 --no-pager || true"))
            print(r.succeed("networkctl status --json=short eth1 | jq -c 'keys, .DHCPv6Client' || true"))
            print(r.succeed("journalctl -u systemd-networkd --no-pager | grep -i -E 'dhcp6|eth1' | tail -30 || true"))
            print(isp.succeed("journalctl -u kea-dhcp6-server --no-pager | tail -30 || true"))
            raise

    def networkd_pid(r):
        return r.succeed("systemctl show -P MainPID systemd-networkd").strip()

    def start_monitors():
        for r in routers:
            r.succeed("rm -f /tmp/link.log /tmp/addr.log")
            r.succeed("systemd-run --unit=mon-link sh -c 'exec ip -o monitor link > /tmp/link.log'")
            r.succeed("systemd-run --unit=mon-addr sh -c 'exec ip -4 -o monitor address > /tmp/addr.log'")

    def check_monitors(phase):
        for r in routers:
            r.succeed("systemctl stop mon-link mon-addr")
            links = r.succeed("cat /tmp/link.log")
            addrs = r.succeed("cat /tmp/addr.log")
            bad_links = [l for l in links.splitlines() if " eth2" in l or " eth3" in l]
            bad_addrs = [
                l for l in addrs.splitlines()
                if (" eth2 " in l or " eth3 " in l) and f"inet {LAN_OK_ADDR}/" not in l
            ]
            assert not bad_links, f"{phase}: {r.name} LAN/mgmt link changed: {bad_links}"
            assert not bad_addrs, f"{phase}: {r.name} LAN/mgmt address changed: {bad_addrs}"
            r.succeed("ip -4 addr show dev eth3 | grep -q 'inet 192.168.100.'")

    start_all()
    isp.wait_for_unit("dnsmasq.service")
    isp.wait_for_unit("kea-dhcp6-server.service")
    for r in routers:
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    with subtest("initial election: router1 owns VIP and WAN, router2 WAN stays down"):
        wait_role(router1, "master")
        wait_role(router2, "backup")
        wait_wan_lease(router1)
        wait_pd(router1)
        assert not wan_up(router2), "backup must keep its WAN link down"
        client.wait_until_succeeds("ping -c1 -W1 10.0.10.1")
        router1.succeed("ip -4 addr show dev eth2 | grep -q 'inet 10.0.10.1/'")

    with subtest("standby: a networkd restart does not raise the WAN"):
        router2.succeed("systemctl restart systemd-networkd")
        router2.sleep(5)
        assert not wan_up(router2), "ActivationPolicy=manual must keep the standby WAN down"

    pids = {r.name: networkd_pid(r) for r in routers}
    start_monitors()

    with subtest("failover: router2 takes VIP, WAN lease and PD; router1 drops WAN"):
        router1.succeed("systemctl stop keepalived")
        wait_role(router2, "master")
        wait_wan_lease(router2)
        wait_pd(router2)
        router1.wait_until_succeeds("! ip -4 addr show dev eth1 | grep -q inet")
        assert not wan_up(router1), "demoted router must bring its WAN down"
        client.wait_until_succeeds("ping -c1 -W1 10.0.10.1")
        router2.succeed("ip -4 addr show dev eth2 | grep -q 'inet 10.0.10.1/'")

    with subtest("fail-back: router1 preempts, router2 releases WAN"):
        router1.succeed("systemctl start keepalived")
        wait_role(router1, "master")
        wait_role(router2, "backup")
        wait_wan_lease(router1)
        wait_pd(router1)
        router2.wait_until_succeeds("! ip -4 addr show dev eth1 | grep -q inet")
        assert not wan_up(router2)
        client.wait_until_succeeds("ping -c1 -W1 10.0.10.1")

    with subtest("LAN and management untouched, systemd-networkd never restarted"):
        check_monitors("failover and fail-back")
        for r in routers:
            assert networkd_pid(r) == pids[r.name], f"{r.name}: systemd-networkd was restarted"
  '';
}
