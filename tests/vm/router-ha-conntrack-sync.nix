{
  self,
  lib,
  pkgs,
}:

# conntrackd state sync (services.router-ha.conntrackSync) on a VRRP pair
# with router-firewall (NAT and the nftables flowtable) as on real routers.
# A LAN client holds a long-lived TCP stream through NAT to the ISP, long
# enough for the flowtable to offload it; the MASTER then loses power. The
# BACKUP must commit the synced flow (offload bits and all, after a bulk
# resync from a restarted conntrackd) before its WAN comes up, so the ISP's
# next packet finds its NAT entry and the stream continues. The ISP sends
# first after the failover, so without sync the new MASTER has no entry for
# it and the stream dies. router1 then reboots, resyncs at startup and
# preempts; router2's demotion takes its WAN down (which deletes its
# masquerade entries) without syncing those deletes, and the stream
# survives the fail-back too.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp mkRouter;

  streamPort = 9000;

  syncModule = local: peer: lanIp: {
    imports = [ self.nixosModules.router-firewall ];
    # A BACKUP's own route to the internet through the MASTER, as
    # nix-clan-homelab uses; on a new MASTER it is the only default route
    # until the WAN lease arrives.
    systemd.network.networks."20-router-lan".routes = [
      {
        Gateway = "10.0.10.1";
        Metric = 2000;
      }
    ];
    services.router-firewall = {
      enable = true;
      wanInterfaces = [ "eth1" ];
      lanInterfaces = [ "eth2" ];
      managementInterfaces = [ "eth3" ];
    };
    services.router-ha = {
      # The pair cold-starts together.
      peerWaitSec = 0;
      # A rebooted router1 stays BACKUP long enough to resync first.
      preemptDelay = 15;
      # A MASTER whose WAN loses carrier yields through the health check.
      wan.healthCheck = {
        enable = true;
        startupGraceSec = 10;
      };
      conntrackSync = {
        enable = true;
        interface = "eth3";
        localAddress = local;
        peerAddress = peer;
        # As nix-clan-homelab: flows that end on the node itself.
        ignoreAddresses = [ lanIp ];
      };
    };
  };

  # Sends a numbered line every 200 ms to whoever connects.
  streamServer = pkgs.writeText "stream-server.py" ''
    import socket, threading, time
    def serve(conn):
        n = 0
        try:
            while True:
                n += 1
                conn.sendall(f"{n}\n".encode())
                time.sleep(0.2)
        except OSError:
            pass
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("198.51.100.1", ${toString streamPort}))
    s.listen()
    while True:
        c, _ = s.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()
  '';

  # A chatty UDP flow from a fixed port, like a WireGuard client.
  udpSender = pkgs.writeText "udp-sender.py" ''
    import socket, time
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("10.0.10.50", 40000))
    while True:
        try:
            s.sendto(b"ping", ("198.51.100.1", 9999))
        except OSError:
            pass
        time.sleep(0.05)
  '';

  # The BACKUP's own long-lived connection (like tailscaled's UDP): a
  # connected socket, so its source address and port never change.
  localSender = pkgs.writeText "local-udp-sender.py" ''
    import socket, time
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("198.51.100.1", 9998))
    while True:
        try:
            s.send(b"ping")
        except OSError:
            pass
        time.sleep(0.05)
  '';

  # Counts lines; records the error and exits if the stream breaks.
  streamClient = pkgs.writeText "stream-client.py" ''
    import os, socket
    s = socket.create_connection(("198.51.100.1", ${toString streamPort}), timeout=10)
    s.settimeout(60)
    lines = 0
    buf = b""
    try:
        while True:
            data = s.recv(4096)
            if not data:
                raise OSError("server closed the stream")
            buf += data
            lines += buf.count(b"\n")
            buf = buf.rsplit(b"\n", 1)[-1]
            with open("/tmp/stream-count.tmp", "w") as f:
                f.write(str(lines))
            os.replace("/tmp/stream-count.tmp", "/tmp/stream-count")
    except OSError as e:
        with open("/tmp/stream-error", "w") as f:
            f.write(repr(e))
  '';
in
mkRouterTest {
  name = "router-ha-conntrack-sync";

  nodes = {
    isp = { pkgs, ... }: {
      imports = [ isp ];
      systemd.services.stream-server = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${streamServer}";
          Restart = "always";
        };
      };
    };

    router1 = mkRouter {
      role = "master";
      lanAddress = "10.0.10.2/24";
      mgmtAddress = "192.168.100.2/24";
      extraModule = syncModule "192.168.100.2" "192.168.100.3" "10.0.10.2";
    };

    router2 = mkRouter {
      role = "backup";
      lanAddress = "10.0.10.3/24";
      mgmtAddress = "192.168.100.3/24";
      extraModule = syncModule "192.168.100.3" "192.168.100.2" "10.0.10.3";
    };

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 2 ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks."10-lan" = {
        matchConfig.Name = "eth1";
        address = [ "10.0.10.50/24" ];
        gateway = [ "10.0.10.1" ];
      };
      environment.systemPackages = [ pkgs.python3 ];
    };
  };

  testScript = ''
    import time

    def wait_role(r, want, timeout=90):
        r.wait_until_succeeds(f"grep -qx {want} /run/router-ha/role", timeout=timeout)

    def count():
        return int(client.succeed("cat /tmp/stream-count 2>/dev/null || echo 0").strip())

    def stream_alive():
        return client.execute("test -e /tmp/stream-error")[0] != 0

    start_all()
    isp.wait_for_unit("stream-server.service")
    for r in [router1, router2]:
        r.wait_for_unit("conntrackd.service")
        r.succeed("test $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal) = 1")
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    with subtest("router1 is MASTER with the WAN lease"):
        wait_role(router1, "master")
        wait_role(router2, "backup")
        router1.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        client.wait_until_succeeds("ping -c1 -W1 198.51.100.1", timeout=60)

    with subtest("a NATed stream is offloaded on router1 and synced to router2"):
        client.succeed("systemd-run --unit stream-client python3 ${streamClient}")
        client.wait_until_succeeds("test $(cat /tmp/stream-count 2>/dev/null || echo 0) -gt 20", timeout=30)
        router1.wait_until_succeeds(
            "conntrack -L -p tcp --dport ${toString streamPort} 2>/dev/null | grep -q OFFLOAD", timeout=30
        )
        router2.wait_until_succeeds(
            "conntrackd -e 2>/dev/null | grep -q 'dport=${toString streamPort}'",
            timeout=30,
        )

    with subtest("a restarted BACKUP gets the offloaded flow by bulk resync"):
        # GOTCHA: a bulk resync copies router1's kernel table, offload bits
        # included (docs/router-ha-pair-guide.md#connection-state-sync).
        # StartupResync fetches router1's table; nobody asks by hand.
        router2.succeed("systemctl restart conntrackd.service")
        router2.wait_until_succeeds("conntrackd -e 2>/dev/null | grep 'dport=${toString streamPort}' | grep -q OFFLOAD", timeout=30)

    with subtest("MASTER power loss: the stream continues through router2"):
        router1.crash()
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        before = count()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline and count() < before + 50:
            assert stream_alive(), "stream broke: " + client.succeed("cat /tmp/stream-error")
            time.sleep(1)
        assert stream_alive(), "stream broke: " + client.succeed("cat /tmp/stream-error")
        assert count() >= before + 50, f"stream stalled at {count()} lines after failover (was {before})"
        # The committed flow carries on in router2's table (re-offloaded or not).
        router2.succeed("conntrack -L -p tcp --dport ${toString streamPort} 2>/dev/null | grep -q 'dport=${toString streamPort}'")
        router2.succeed("journalctl -u conntrackd --no-pager | grep -qE 'Committed [1-9][0-9]* new entries'")

    with subtest("router1 reboots, resyncs as BACKUP, preempts: the stream survives the fail-back"):
        router1.start()
        wait_role(router1, "backup", timeout=120)
        router1.wait_until_succeeds("conntrackd -e 2>/dev/null | grep -q 'dport=${toString streamPort}'", timeout=30)
        wait_role(router1, "master", timeout=60)
        wait_role(router2, "backup", timeout=30)
        router1.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        before = count()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline and count() < before + 50:
            assert stream_alive(), "stream broke on fail-back: " + client.succeed("cat /tmp/stream-error")
            time.sleep(1)
        assert stream_alive(), "stream broke on fail-back: " + client.succeed("cat /tmp/stream-error")
        assert count() >= before + 50, f"stream stalled at {count()} lines after fail-back (was {before})"

    with subtest("keepalived stopped on the MASTER (a deploy): its WAN goes down, router2 still has the flow"):
        # GOTCHA: stopping keepalived sends a priority-0 advert and takes the
        # WAN down at once; the kernel deletes the WAN's masquerade entries.
        # Those deletes must not reach router2 before it commits.
        before = count()
        stop_start = time.monotonic()
        router1.succeed("systemctl stop keepalived.service")
        took = time.monotonic() - stop_start
        assert took < 20, f"stopping keepalived took {took:.0f} s (a transition blocked)"
        # With the WAN health check, IgnoreCarrierLoss keeps the demoted WAN's
        # address for the check's detection time (13 s here).
        router1.wait_until_succeeds("! ip -4 addr show dev eth1 | grep -q inet", timeout=30)
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        t0 = time.monotonic()
        deadline = t0 + 60
        while time.monotonic() < deadline and count() < before + 50:
            print(f"keepalived-stop: +{time.monotonic() - t0:.1f}s lines {count() - before}")
            if not stream_alive():
                print(router2.succeed("conntrack -L -p tcp --dport ${toString streamPort} 2>&1; conntrackd -e 2>&1 | grep ${toString streamPort}; journalctl -u conntrackd --no-pager | tail -20"))
            assert stream_alive(), "stream broke on keepalived stop: " + client.succeed("cat /tmp/stream-error")
            time.sleep(1)
        assert count() >= before + 50, f"stream stalled at {count()} lines after keepalived stop (was {before})"

    with subtest("a flow the new MASTER has no synced entry for is NATed once the WAN is up"):
        # Between promotion and the lease's route only the LAN fallback route
        # exists; a packet of this flow must not leave un-NATed then.
        client.succeed("systemd-run --unit udp-sender python3 ${udpSender}")
        router2.wait_until_succeeds("conntrack -L -p udp --dport 9999 2>/dev/null | grep -q 'dst=198.51.100.50'", timeout=30)
        router1.succeed("systemctl stop conntrackd.service")
        router1.succeed("systemctl start keepalived.service")
        wait_role(router1, "master", timeout=90)
        router1.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        time.sleep(3)
        srcs = isp.succeed("timeout 5 ${pkgs.tcpdump}/bin/tcpdump -n -i eth1 -c 20 'udp and dst port 9999' 2>/dev/null | awk '{print $3}' | sed 's/\\.[0-9]*$//' | sort | uniq -c")
        print(srcs)
        assert "198.51.100.50" in srcs, f"no NATed packets of the UDP flow reach the ISP: {srcs}"
        assert "10.0.10." not in srcs, f"the UDP flow leaves the WAN un-NATed: {srcs}"

    with subtest("the BACKUP's own long-lived connection is NATed after it is promoted"):
        # router2 (BACKUP) reaches the ISP through router1 by its LAN fallback
        # route; its own conntrack entry for this socket has no NAT, as it
        # should. Once router2 is MASTER the same tuple leaves its WAN: the
        # commit replaces router2's entry with router1's synced, NATed one.
        router2.succeed("systemd-run --unit local-sender ${pkgs.python3}/bin/python3 ${localSender}")
        router1.wait_until_succeeds("conntrack -L -p udp --dport 9998 2>/dev/null | grep -q 'dst=198.51.100.50'", timeout=30)
        # router2 must hold router1's NATed copy before router1 goes away.
        # (conntrackd -e prints the original tuple only; the NAT travels with it.)
        router2.wait_until_succeeds("conntrackd -e 2>/dev/null | grep -q 'src=10.0.10.3 dst=198.51.100.1 .*dport=9998'", timeout=30)
        router1.succeed("systemctl stop keepalived.service")
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        time.sleep(3)
        srcs = isp.succeed("timeout 5 ${pkgs.tcpdump}/bin/tcpdump -n -i eth1 -c 20 'udp and dst port 9998' 2>/dev/null | awk '{print $3}' | sed 's/\\.[0-9]*$//' | sort | uniq -c")
        print(srcs)
        assert "198.51.100.50" in srcs, f"no NATed packets of router2's own flow reach the ISP: {srcs}"
        assert "10.0.10." not in srcs, f"router2's own flow leaves the WAN un-NATed: {srcs}"
    with subtest("the MASTER's WAN cable is pulled: the stream survives the health-check handover"):
        # GOTCHA: on carrier loss networkd would drop the WAN address and the
        # kernel the masquerade entries, synced to router2 before the health
        # check yields; IgnoreCarrierLoss keeps them until the demotion.
        # Earlier subtests left router1's conntrackd and keepalived stopped,
        # and the old stream went through router1 unsynced: bring router1
        # back as MASTER with sync, then start a fresh stream that router2
        # learns from live events.
        router1.succeed("systemctl start conntrackd.service keepalived.service")
        wait_role(router1, "master", timeout=90)
        router1.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        client.succeed("systemctl stop stream-client.service || true; rm -f /tmp/stream-count /tmp/stream-error")
        client.succeed("systemd-run --unit stream-client2 python3 ${streamClient}")
        client.wait_until_succeeds("test $(cat /tmp/stream-count 2>/dev/null || echo 0) -gt 20", timeout=30)
        sport = client.succeed("ss -tnH state established '( dport = :${toString streamPort} )' | awk '{print $3}' | sed 's/.*://' | head -1").strip()
        router2.wait_until_succeeds(f"conntrackd -e 2>/dev/null | grep -q 'sport={sport} dport=${toString streamPort}'", timeout=30)
        before = count()
        router1.send_monitor_command("set_link vlan1 off")
        wait_role(router2, "master", timeout=90)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline and count() < before + 50:
            assert stream_alive(), "stream broke on WAN carrier loss: " + client.succeed("cat /tmp/stream-error")
            time.sleep(1)
        assert stream_alive(), "stream broke on WAN carrier loss: " + client.succeed("cat /tmp/stream-error")
        assert count() >= before + 50, f"stream stalled at {count()} lines after WAN carrier loss (was {before})"
        router1.send_monitor_command("set_link vlan1 on")
  '';
}
