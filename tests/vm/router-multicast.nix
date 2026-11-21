{
  self,
  lib,
  pkgs,
}:

# IGMP proxy for IPTV-style streams. A source on the upstream VLAN (vlan 1)
# streams 239.1.1.1 from a remote address (192.0.2.10) while the router's
# default route points elsewhere and all.rp_filter is strict, as on a router
# with the IPTV service on its own VLAN. A receiver on the lan (vlan 2) joins
# and gets the stream, stops getting it after leaving, and a receiver on
# another VLAN (vlan 3) never gets it.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  group = "239.1.1.1";
  port = 5000;

  receiverScript = pkgs.writeText "mcast-recv.py" ''
    import socket, struct, sys, time
    group, port, seconds, local = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, struct.pack("4s4s", socket.inet_aton(group), socket.inet_aton(local)))
    s.settimeout(0.5)
    n, end = 0, time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            s.recv(2048)
            n += 1
        except socket.timeout:
            pass
    s.close()  # sends the IGMP leave
    print(n)
  '';

  senderScript = pkgs.writeText "mcast-send.py" ''
    import socket, sys, time
    group, port, src = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.bind((src, 0))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 8)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(src))
    while True:
        s.sendto(b"iptv", (group, port))
        time.sleep(0.05)
  '';

  receiver = vlan: address: gateway: { pkgs, ... }: {
    virtualisation.vlans = [ vlan ];
    networking = {
      useNetworkd = true;
      useDHCP = false;
      firewall.enable = false;
    };
    systemd.network.networks."10-lan" = {
      matchConfig.Name = "eth1";
      address = [ "${address}/24" ];
      # A client's default route; without one its own rp_filter (loose by
      # systemd default) drops the remote-source stream.
      routes = [ { Gateway = gateway; } ];
    };
    # GOTCHA: igmpproxy treats IGMPv3 reports as any-source joins; IGMPv2
    # keeps the test independent of that (docs/router-multicast.md).
    boot.kernel.sysctl."net.ipv4.conf.eth1.force_igmp_version" = 2;
    environment.systemPackages = [ pkgs.python3 pkgs.tcpdump ];
  };
in
mkRouterTest {
  name = "router-multicast";

  nodes = {
    source = { pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks."10-iptv" = {
        matchConfig.Name = "eth1";
        address = [
          "10.0.99.2/24"
          "192.0.2.10/32"
        ];
        routes = [ { Destination = "224.0.0.0/4"; } ];
      };
      environment.systemPackages = [ pkgs.python3 ];
    };

    router = { pkgs, ... }: {
      imports = [
        self.nixosModules.router-firewall
        self.nixosModules.router-multicast
      ];
      virtualisation.vlans = [
        1
        2
        3
      ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks = {
        "10-iptv" = {
          matchConfig.Name = "eth1";
          address = [ "10.0.99.1/24" ];
        };
        "20-lan" = {
          matchConfig.Name = "eth2";
          address = [ "10.0.10.1/24" ];
        };
        "20-iot" = {
          matchConfig.Name = "eth3";
          address = [ "10.0.20.1/24" ];
          # The default route is not via the IPTV VLAN, so strict
          # reverse-path filtering would drop the remote source.
          routes = [ { Gateway = "10.0.20.254"; GatewayOnLink = true; } ];
        };
      };
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth1" ];
        lanInterfaces = [
          "eth2"
          "eth3"
        ];
      };

      services.router-multicast = {
        enable = true;
        upstream.interface = "eth1";
        downstreams = [ "eth2" ];
      };
      environment.systemPackages = [ pkgs.iproute2 ];
    };

    lan = receiver 2 "10.0.10.50" "10.0.10.1";
    iot = receiver 3 "10.0.20.50" "10.0.20.1";
  };

  testScript = ''
    import threading

    start_all()
    router.wait_for_unit("router-multicast.service")
    source.wait_for_unit("systemd-networkd.service")
    source.succeed("systemd-run --unit mcast-send python3 ${senderScript} ${group} ${toString port} 192.0.2.10")
    for r in (lan, iot):
        r.wait_for_unit("systemd-networkd.service")
        r.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q inet")

    with subtest("upstream rp_filter is loose despite a strict all"):
        assert router.succeed("cat /proc/sys/net/ipv4/conf/eth1/rp_filter").strip() == "2"

    with subtest("lan receiver gets the stream; iot receiver never does"):
        results = {}
        def recv(node, local):
            results[node.name] = int(node.succeed(f"python3 ${receiverScript} ${group} ${toString port} 15 {local}").strip())
        threads = [threading.Thread(target=recv, args=a) for a in ((lan, "10.0.10.50"), (iot, "10.0.20.50"))]
        for th in threads:
            th.start()
        router.wait_until_succeeds("ip mroute show | grep '(192.0.2.10,${group})' | grep -q 'Oifs: eth2'", timeout=15)
        print(router.succeed("ip mroute show"))
        for th in threads:
            th.join()
        print(f"received: {results}")
        assert results["lan"] > 20, f"lan received {results['lan']} packets"
        assert results["iot"] == 0, f"iot received {results['iot']} packets"

    with subtest("the stream stops on the lan after the leave"):
        # quickleave: igmpproxy queries once more, then drops the route.
        router.wait_until_succeeds("! ip mroute show | grep '(192.0.2.10,${group})' | grep -q eth2", timeout=20)
        print(router.succeed("ip mroute show"))
        # Let packets already queued drain, then the link must stay silent.
        lan.sleep(2)
        seen = lan.succeed("timeout 5 tcpdump -ni eth1 -c 1000 'udp and dst host ${group}' 2>/dev/null || true").strip()
        assert seen == "", f"lan still sees the stream after leaving:\n{seen}"
  '';
}
