{
  self,
  lib,
  pkgs,
}:

# Downstream IPv6 as documented in docs/router-ipv6-downstream.md: the router
# takes a /56 from the ISP (DHCPv6-PD) and gives each routed segment a /64 by
# subnet ID, announced in RAs for SLAAC. Clients on two segments must get an
# address in their own /64, a default route via the router, RDNSS, and reach
# the ISP. The iot segment uses prefixDelegationMode = "managed": no DHCPv6
# server answers, and clients still configure by SLAAC.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp;

  client = vlan: {
    virtualisation.vlans = [ vlan ];
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    services.resolved.enable = true;
    systemd.network.networks."10-lan" = {
      matchConfig.Name = "eth1";
      networkConfig.IPv6AcceptRA = true;
    };
  };

  dnsServer = "2001:db8:53::53";
in
mkRouterTest {
  name = "router-ipv6-downstream";

  nodes = {
    inherit isp;

    router = {
      imports = [ self.nixosModules.router-networking ];
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
        routedInterfaces = {
          lan = {
            device = "eth2";
            ipv4Address = "10.0.10.1/24";
            ipv6SubnetId = "0x1";
            dns = [ dnsServer ];
          };
          iot = {
            device = "eth3";
            ipv4Address = "10.0.20.1/24";
            ipv6SubnetId = "0x2";
            prefixDelegationMode = "managed";
          };
        };
      };
    };

    lanClient = client 2;
    iotClient = client 3;
  };

  testScript = ''
    import ipaddress

    def global6(m, dev):
        out = m.succeed(f"ip -6 -o addr show dev {dev} scope global -tentative | awk '{{print $4}}'")
        return [ipaddress.ip_interface(a) for a in out.split()]

    def wait_global6(m, dev, timeout=90):
        m.wait_until_succeeds(f"ip -6 -o addr show dev {dev} scope global -tentative | grep -q inet6", timeout=timeout)
        return global6(m, dev)

    start_all()
    isp.wait_for_unit("kea-dhcp6-server.service")
    isp.wait_for_unit("radvd.service")

    with subtest("router gets a /56 and gives each segment its own /64 by subnet ID"):
        lan_net = wait_global6(router, "eth2")[0].network
        iot_net = wait_global6(router, "eth3")[0].network
        print(f"lan {lan_net}, iot {iot_net}")
        pd = ipaddress.ip_network("2001:db8:100::/40")
        assert lan_net.prefixlen == 64 and iot_net.prefixlen == 64
        assert lan_net.subnet_of(pd) and iot_net.subnet_of(pd), "segment prefixes must come from the ISP delegation"
        assert (int(lan_net.network_address) >> 64) & 0xff == 1, f"lan subnet ID is not 1: {lan_net}"
        assert (int(iot_net.network_address) >> 64) & 0xff == 2, f"iot subnet ID is not 2: {iot_net}"

    with subtest("clients form SLAAC addresses in their own /64"):
        for c, net in ((lanClient, lan_net), (iotClient, iot_net)):
            addrs = wait_global6(c, "eth1")
            assert any(a.ip in net for a in addrs), f"{c.name} has {addrs}, expected one in {net}"

    with subtest("default route via the router and RDNSS on the lan segment"):
        ll = router.succeed("ip -6 -o addr show dev eth2 scope link | awk '{print $4}' | cut -d/ -f1").strip()
        lanClient.wait_until_succeeds(f"ip -6 route show default | grep -q 'via {ll}'", timeout=30)
        lanClient.wait_until_succeeds("resolvectl dns eth1 | grep -q '${dnsServer}'", timeout=30)

    with subtest("clients reach the ISP over IPv6"):
        wan = [a for a in global6(router, "eth1") if a.ip in ipaddress.ip_network("2001:db8:1::/64")][0].ip
        # The test ISP installs no route for delegated prefixes; add it.
        isp.succeed(f"ip -6 route replace 2001:db8:100::/40 via {wan} dev eth1")
        lanClient.succeed("ping -6 -c2 -W3 2001:db8:1::1")
        iotClient.succeed("ping -6 -c2 -W3 2001:db8:1::1")
  '';
}
