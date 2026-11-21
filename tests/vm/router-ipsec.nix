{
  self,
  lib,
  pkgs,
}:

# Route-based IPsec between two routers across a shared WAN (vlan 1): a PSK
# IKEv2 tunnel bound to an XFRM interface on each side, BGP over the tunnel
# advertising each side's LAN, and router-firewall admitting IKE/ESP only on
# the WAN from the peer. Checks the SA, ping through the XFRM interface, BGP
# Established, LAN-to-LAN routing over BGP, ESP-only on the wire, and no
# cleartext when the SA is gone.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  psk = "vm-test-only-psk-0123456789";

  mkSite =
    {
      wan,
      peerWan,
      lan,
      lanNet,
      peerLanNet,
      tunnel,
      peerTunnel,
      asn,
      peerAsn,
      initiate,
      lanVlan,
    }:
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.router-firewall
        self.nixosModules.router-bgp
        self.nixosModules.router-ipsec
      ];
      virtualisation.vlans = [
        1
        lanVlan
      ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
      systemd.network.networks = {
        "10-wan" = {
          matchConfig.Name = "eth1";
          address = [ "${wan}/24" ];
        };
        "20-lan" = {
          matchConfig.Name = "eth2";
          address = [ "${lan}/24" ];
        };
      };

      # Test-only key; real deployments point pskFile at a secret manager path.
      environment.etc."ipsec/site.psk".text = psk;

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth1" ];
        lanInterfaces = [ "eth2" ];
      };

      services.router-ipsec = {
        enable = true;
        tunnels.site = {
          ifId = 10;
          address = "${tunnel}/30";
          remote.address = peerWan;
          local.address = wan;
          pskFile = "/etc/ipsec/site.psk";
          inherit initiate;
        };
      };

      services.router-bgp = {
        enable = true;
        inherit asn;
        routerId = wan;
        addressFamilies.ipv4Unicast.networks = [ lanNet ];
        neighbors.${peerTunnel} = {
          remoteAs = peerAsn;
          importPolicy.ipv4Unicast.allowCidrs = [ peerLanNet ];
          exportPolicy.ipv4Unicast.allowCidrs = [ lanNet ];
        };
      };

      environment.systemPackages = [
        pkgs.tcpdump
        pkgs.strongswan
      ];
    };
in
mkRouterTest {
  name = "router-ipsec";

  nodes = {
    left = mkSite {
      wan = "192.0.2.1";
      peerWan = "192.0.2.2";
      lan = "10.1.0.1";
      lanNet = "10.1.0.0/24";
      peerLanNet = "10.2.0.0/24";
      tunnel = "169.254.10.1";
      peerTunnel = "169.254.10.2";
      asn = 65001;
      peerAsn = 65002;
      initiate = true;
      lanVlan = 2;
    };
    right = mkSite {
      wan = "192.0.2.2";
      peerWan = "192.0.2.1";
      lan = "10.2.0.1";
      lanNet = "10.2.0.0/24";
      peerLanNet = "10.1.0.0/24";
      tunnel = "169.254.10.2";
      peerTunnel = "169.254.10.1";
      asn = 65002;
      peerAsn = 65001;
      initiate = false;
      lanVlan = 3;
    };
  };

  testScript = ''
    start_all()
    for r in (left, right):
        r.wait_for_unit("strongswan-swanctl.service")
        r.wait_until_succeeds("ip link show xfrm-site")

    with subtest("the IKE and child SAs are established"):
        left.wait_until_succeeds("swanctl --list-sas | grep -q 'site.*ESTABLISHED'", timeout=60)
        left.wait_until_succeeds("swanctl --list-sas | grep -A20 'site' | grep -q 'INSTALLED'", timeout=60)
        print(left.succeed("swanctl --list-sas"))

    with subtest("ping through the XFRM interface"):
        left.wait_until_succeeds("ping -c1 -W2 169.254.10.2", timeout=30)

    with subtest("BGP is Established over the tunnel and routes each LAN through it"):
        left.wait_until_succeeds("vtysh -c 'show bgp summary' | grep 169.254.10.2 | grep -qv -E 'Idle|Active|Connect'", timeout=90)
        left.wait_until_succeeds("ip route show 10.2.0.0/24 | grep -q 'dev xfrm-site'", timeout=60)
        right.wait_until_succeeds("ip route show 10.1.0.0/24 | grep -q 'dev xfrm-site'", timeout=60)
        left.succeed("ping -c2 -W2 -I 10.1.0.1 10.2.0.1")

    with subtest("only ESP crosses the WAN"):
        left.succeed("timeout 6 tcpdump -ni eth1 -w /tmp/wan.pcap 'host 192.0.2.2' >/dev/null 2>&1 & sleep 1; ping -c3 -W2 -I 10.1.0.1 10.2.0.1; wait || true")
        esp = int(left.succeed("tcpdump -nr /tmp/wan.pcap esp 2>/dev/null | wc -l").strip())
        clear = int(left.succeed("tcpdump -nr /tmp/wan.pcap icmp 2>/dev/null | wc -l").strip())
        print(f"esp={esp} icmp={clear}")
        assert esp >= 6 and clear == 0, f"expected ESP only on the WAN, got esp={esp} icmp={clear}"

    with subtest("no cleartext fallback when the SA is gone"):
        left.succeed("systemctl stop strongswan-swanctl.service")
        left.wait_until_fails("ip xfrm state | grep -q proto")
        left.succeed("timeout 5 tcpdump -ni eth1 -w /tmp/down.pcap 'host 192.0.2.2' >/dev/null 2>&1 & sleep 1; ping -c3 -W1 -I 10.1.0.1 10.2.0.1 || true; ping -c2 -W1 169.254.10.2 || true; wait || true")
        clear = int(left.succeed("tcpdump -nr /tmp/down.pcap icmp 2>/dev/null | wc -l").strip())
        assert clear == 0, f"{clear} ICMP packets left in clear without an SA"
  '';
}
