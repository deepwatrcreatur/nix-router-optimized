{
  self,
  lib,
  pkgs,
}:

# Two routers run Kea DHCPv4 with the HA hook on a shared LAN (vlan 1). A
# client asks for leases from many MAC addresses with busybox udhcpc, so each
# request looks like a fresh client. Covers the evidence the re-entry gate in
# docs/router-kea-ha-reentry-gate.md asks for: HA state on both nodes, lease
# sync, failover to the surviving peer, and clean fail-back.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  mkRouter =
    {
      name,
      peer,
      role,
      address,
      peerAddress,
      setLocalAddress ? true,
    }:
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.router-kea
        self.nixosModules.router-firewall
      ];

      # vlan 2 is an unused WAN; router-firewall needs one.
      virtualisation.vlans = [
        1
        2
      ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-lan" = {
        matchConfig.Name = "eth1";
        address = [ "${address}/24" ];
      };

      # The real input policy, so the test proves only the peer reaches the
      # HA port while DHCP stays open to clients.
      services.router-firewall = {
        enable = true;
        lanInterfaces = [ "eth1" ];
        wanInterfaces = [ "eth2" ];
      };

      services.router-kea = {
        enable = true;
        exporter.enable = false;
        dhcp4 = {
          interfaces = [ "eth1" ];
          subnet = "10.0.10.0/24";
          gatewayAddress = "10.0.10.1";
          poolRanges = [
            {
              start = "10.0.10.100";
              end = "10.0.10.199";
            }
          ];
          ha = {
            enable = true;
            thisServerName = name;
            peerName = peer;
            inherit role peerAddress;
          }
          # router2 keeps the 0.0.0.0 default: this URL only sets where Kea
          # listens; the peer reaches it through its own peerAddress.
          // lib.optionalAttrs setLocalAddress { localAddress = address; };
        };
      };

      environment.systemPackages = [
        pkgs.socat
        pkgs.jq
        pkgs.curl
      ];
    };

  udhcpcScript = pkgs.writeShellScript "udhcpc-report" ''
    if [ "$1" = bound ]; then
      echo "LEASE $ip $serverid"
    fi
  '';
in
mkRouterTest {
  name = "router-kea-ha";

  nodes = {
    router1 = mkRouter {
      name = "router1";
      peer = "router2";
      role = "primary";
      address = "10.0.10.2";
      peerAddress = "10.0.10.3";
    };

    router2 = mkRouter {
      name = "router2";
      peer = "router1";
      role = "secondary";
      address = "10.0.10.3";
      peerAddress = "10.0.10.2";
      setLocalAddress = false;
    };

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useDHCP = false;
        firewall.enable = false;
      };
      environment.systemPackages = [ pkgs.busybox ];
    };
  };

  testScript = ''
    import json
    import time

    routers = [router1, router2]

    def kea(r, command, **arguments):
        msg = {"command": command}
        if arguments:
            msg["arguments"] = arguments
        out = r.succeed(f"echo '{json.dumps(msg)}' | socat - UNIX-CONNECT:/run/kea/dhcp4.sock")
        return json.loads(out)

    def ha_state(r):
        # The socket is missing for a moment after a restart.
        status, out = r.execute("echo '{\"command\": \"ha-heartbeat\"}' | socat - UNIX-CONNECT:/run/kea/dhcp4.sock")
        if status != 0:
            return "no-socket"
        resp = json.loads(out)
        return resp.get("arguments", {}).get("state", f"error: {resp}")

    def wait_state(r, *states, timeout=120):
        def check(_):
            s = ha_state(r)
            r.log(f"HA state: {s}")
            return s in states
        retry(check, timeout)

    def lease(mac):
        client.succeed(f"ip link set dev eth1 down && ip link set dev eth1 address {mac} && ip link set dev eth1 up")
        out = client.succeed(
            "busybox udhcpc -i eth1 -q -n -f -t 5 -T 2 -s ${udhcpcScript} 2>/dev/null || true"
        )
        for line in out.splitlines():
            if line.startswith("LEASE "):
                _, ip, server = line.split()
                return ip, server
        return None

    def lease_mac(r, ip):
        resp = kea(r, "lease4-get", **{"ip-address": ip})
        if resp["result"] != 0:
            return None
        return resp["arguments"]["hw-address"]

    leases = {}  # mac -> ip, across every phase

    macs = [f"02:00:00:00:10:{i:02x}" for i in range(1, 9)]
    failover_macs = [f"02:00:00:00:20:{i:02x}" for i in range(1, 9)]

    start_all()
    for r in routers:
        r.wait_for_unit("kea-dhcp4-server.service")
    client.succeed("ip link set dev eth1 up")

    with subtest("both nodes reach load-balancing"):
        for r in routers:
            wait_state(r, "load-balancing")

    with subtest("only the peer can reach the HA port"):
        router1.succeed("curl -s -m 5 -o /dev/null http://10.0.10.3:8000/")
        router2.succeed("curl -s -m 5 -o /dev/null http://10.0.10.2:8000/")
        client.succeed("ip addr add 10.0.10.250/24 dev eth1")
        for addr in ["10.0.10.2", "10.0.10.3"]:
            client.fail(f"busybox nc -z -w 3 {addr} 8000")
        client.succeed("ip addr flush dev eth1")

    with subtest("fresh clients get leases and both nodes record every lease"):
        servers = set()
        for mac in macs:
            got = lease(mac)
            assert got, f"no lease for {mac}"
            ip, server = got
            servers.add(server)
            leases[mac] = ip
            for r in routers:
                r.wait_until_succeeds(
                    f"echo '{{\"command\":\"lease4-get\",\"arguments\":{{\"ip-address\":\"{ip}\"}}}}'"
                    " | socat - UNIX-CONNECT:/run/kea/dhcp4.sock | jq -e '.result == 0'",
                    timeout=10,
                )
        print(f"servers that answered: {servers}")
        assert servers == {"10.0.10.2", "10.0.10.3"}, f"load balancing used only {servers}"

    with subtest("primary stops: secondary goes partner-down and serves everyone"):
        router1.succeed("systemctl stop kea-dhcp4-server")
        t0 = time.monotonic()
        # Defaults: 15 s max-response-delay plus up to one 5 s heartbeat.
        wait_state(router2, "partner-down", timeout=40)
        print(f"takeover after {time.monotonic() - t0:.1f} s")
        for mac in failover_macs:
            got = lease(mac)
            assert got, f"no lease for {mac} during failover"
            assert got[1] == "10.0.10.3", f"unexpected server {got}"
            leases[mac] = got[0]

    with subtest("primary returns: syncs leases and both go back to load-balancing"):
        router1.succeed("systemctl start kea-dhcp4-server")
        for r in routers:
            wait_state(r, "load-balancing", timeout=180)
        # Check router1's database before any new DHCP traffic, so only the
        # startup sync can have put these leases there.
        for mac in failover_macs:
            ip = leases[mac]
            assert lease_mac(router1, ip) == mac, f"router1 did not sync {ip} -> {mac} from the failover"
        ips = list(leases.values())
        assert len(set(ips)) == len(ips), f"duplicate leases across phases: {leases}"
        # Clients keep their failover addresses after fail-back.
        for mac in failover_macs:
            got = lease(mac)
            assert got and got[0] == leases[mac], f"{mac} moved from {leases[mac]} to {got}"
  '';
}
