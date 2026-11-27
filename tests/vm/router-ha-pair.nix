{
  self,
  lib,
  pkgs,
}:

# VRRP lifecycle on two routers with preemptDelay and single-active units:
# election, crash of the MASTER, delayed fail-back, FAULT on LAN loss, and a
# reboot and a power loss of the MASTER. At every steady state exactly one
# node holds the VIP, the WAN link and the owned units (a stand-in,
# inadyn.timer, miniupnpd, LAN RAs), and a LAN client's only IPv6 default
# router is the virtual link-local, resolved to that node's MAC, sampled
# for a few seconds.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp mkRouter;

  preemptDelay = 10;
  peerWaitSec = 15;

  pairModule =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.router-ddns
        self.nixosModules.router-upnp
      ];

      # Typed owners: router-ha starts inadyn (timer), miniupnpd and the RA
      # drop-in on MASTER only. inadyn fails without internet; the test
      # watches its timer.
      # miniupnpd's iptables build needs legacy iptables; routers use nftables.
      networking.nftables.enable = true;
      environment.etc."router-ddns/token".text = "vmtest";
      services.router-ddns = {
        enable = true;
        ha.singleActiveOwner = true;
        cloudflare = {
          zoneName = "example.net";
          labels = [ "home" ];
          apiTokenFile = "/etc/router-ddns/token";
        };
      };
      services.router-upnp = {
        enable = true;
        internalIPs = [ "eth2" ];
        ha.singleActiveOwner = true;
      };

      services.router-ha = {
        inherit preemptDelay peerWaitSec;
        singleActiveUnits = [ "ha-owned.service" ];
      };
      # Stands in for a service only the active router may run (inadyn, a
      # DDNS updater). router-ha alone starts and stops it.
      systemd.services.ha-owned = {
        description = "Single-active stand-in for the router HA test";
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
in
mkRouterTest {
  name = "router-ha-pair";

  nodes = {
    inherit isp;

    router1 = mkRouter {
      role = "master";
      lanAddress = "10.0.10.2/24";
      mgmtAddress = "192.168.100.2/24";
      extraModule = pairModule;
    };

    router2 = mkRouter {
      role = "backup";
      lanAddress = "10.0.10.3/24";
      mgmtAddress = "192.168.100.3/24";
      extraModule = pairModule;
    };

    # Learns its IPv6 default router from RAs; only the MASTER may send them.
    client = {
      virtualisation.vlans = [ 2 ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network.networks."10-lan" = {
        matchConfig.Name = "eth1";
        address = [ "10.0.10.50/24" ];
        networkConfig.IPv6AcceptRA = true;
      };
    };
  };

  testScript = ''
    import time

    routers = [router1, router2]
    PREEMPT_DELAY = ${toString preemptDelay}
    PEER_WAIT = ${toString peerWaitSec}

    def role(r):
        return r.succeed("cat /run/router-ha/role 2>/dev/null || echo none").strip()

    def wait_role(r, *roles, timeout=60):
        def check(_):
            return role(r) in roles
        retry(check, timeout)

    def wan_up(r):
        return "UP" in r.succeed("ip -o link show dev eth1").split(">")[0]

    def has_vip(r):
        return r.execute("ip -4 addr show dev eth2 | grep -q 'inet 10.0.10.1/'")[0] == 0

    OWNED = ["ha-owned.service", "inadyn.timer", "miniupnpd.service", "router-ha-ra-owner.service"]

    def owned_active(r):
        return all(r.execute(f"systemctl is-active --quiet {u}")[0] == 0 for u in OWNED)

    def owned_inactive(r):
        return all(r.execute(f"systemctl is-active --quiet {u}")[0] != 0 for u in OWNED)

    VLL = "fe80::1"
    MAC = {}

    def lan_mac(r):
        if r.name not in MAC:
            MAC[r.name] = r.succeed("cat /sys/class/net/eth2/address").strip()
        return MAC[r.name]

    def client_routers():
        # Default routes learned from RAs: one "via fe80::..." per router.
        out = client.succeed("ip -6 route show default dev eth1 proto ra")
        return sorted(l.split("via ")[1].split()[0] for l in out.splitlines() if "via " in l)

    def client_router_mac():
        out = client.succeed(f"ip -6 neigh show {VLL} dev eth1").split()
        return out[out.index("lladdr") + 1] if "lladdr" in out else None

    def expected_routers(master, others):
        # The MASTER advertises only from the virtual link-local; each node's
        # own address advertises lifetime 0, so a dead MASTER leaves nothing
        # stale behind.
        return lambda routers: routers == [VLL]

    def assert_ra_owner(master, others):
        ok = expected_routers(master, others)
        retry(lambda _: ok(client_routers()), 40)
        # Unsolicited NA on promotion, else NUD, moves the router's MAC.
        client.succeed(f"ping -6 -c1 -W1 {VLL}%eth1 >/dev/null || true")
        retry(lambda _: client_router_mac() == lan_mac(master), 30)

    def keepalived_running(r):
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    def assert_steady(master, others, hold=5):
        """Exactly one owner: wait for the handover to finish, then sample."""
        wait_role(master, "master")
        master.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        retry(lambda _: owned_active(master), 30)
        for r in others:
            retry(lambda _: owned_inactive(r), 30)
            r.wait_until_succeeds("! ip -4 addr show dev eth1 | grep -q inet", timeout=30)
        # The demoted node's final RA (lifetime 0) removes it at once; the new
        # MASTER advertises as soon as its drop-in lands.
        assert_ra_owner(master, others)
        end = time.monotonic() + hold
        while time.monotonic() < end:
            assert role(master) == "master", f"{master.name} lost MASTER"
            assert wan_up(master) and has_vip(master) and owned_active(master), f"{master.name} lost ownership"
            for r in others:
                assert role(r) in ("backup", "fault"), f"{r.name} is {role(r)} next to {master.name}"
                assert not wan_up(r), f"both {master.name} and {r.name} hold the WAN"
                assert not has_vip(r), f"both {master.name} and {r.name} hold the VIP"
                assert owned_inactive(r), f"owned units run on {r.name} and {master.name}"
            assert expected_routers(master, others)(client_routers()), f"client routers {client_routers()}, MASTER {master.name}"
            time.sleep(0.5)

    def seconds_since_backup(r):
        """VM-clock seconds since keepalived last entered BACKUP on r."""
        # GOTCHA: preempt_delay counts from keepalived's start or from the
        # LAN coming back, not from when this script notices, so measure it
        # on the router's own clock (role file mtime).
        return float(r.succeed(
            "echo $(( $(date +%s%N) - $(stat -c %Y /run/router-ha/role)000000000 )) | awk '{print $1/1e9}'"
        ).strip())

    def assert_delayed_failback(new_master, old_master):
        """The recovered higher-priority node waits preemptDelay as BACKUP."""
        wait_role(old_master, "backup")
        hold = PREEMPT_DELAY - seconds_since_backup(old_master) - 2
        assert hold > 2, f"too little of preemptDelay left to observe ({hold:.1f} s)"
        end = time.monotonic() + hold
        while time.monotonic() < end:
            assert role(new_master) == "master", f"{old_master.name} preempted before preemptDelay"
            assert not wan_up(old_master), f"{old_master.name} raised its WAN while BACKUP"
            assert not has_vip(old_master), f"{old_master.name} took the VIP while BACKUP"
            assert owned_inactive(old_master), f"owned units run on BACKUP {old_master.name}"
            time.sleep(0.5)
        wait_role(old_master, "master", timeout=PREEMPT_DELAY + 30)
        assert_steady(old_master, [new_master])

    start_all()
    isp.wait_for_unit("dnsmasq.service")
    isp.wait_for_unit("radvd.service")
    for r in routers:
        keepalived_running(r)
    client.wait_for_unit("systemd-networkd.service")
    for r in routers:
        lan_mac(r)

    with subtest("election: router1 (priority 100) owns VIP, WAN and the unit"):
        assert_steady(router1, [router2])

    with subtest("notify events apply in keepalived's order"):
        # MASTER then FAULT back to back, as keepalived sends them when a
        # fresh MASTER loses its LAN. Concurrent notify scripts could finish
        # MASTER last and leave the WAN up on a FAULT node.
        # Another instance's event first: the reader must ignore it.
        router1.succeed("""printf 'INSTANCE "other" BACKUP 50\\n' > /run/router-ha/notify.fifo""")
        time.sleep(2)
        assert role(router1) == "master" and wan_up(router1) and owned_active(router1), "another instance's BACKUP demoted router1"
        router1.succeed("""printf 'INSTANCE "main" MASTER 100\\nINSTANCE "main" FAULT 100\\n' > /run/router-ha/notify.fifo""")
        # The role file is written first; wait for the whole demotion.
        retry(lambda _: role(router1) == "fault" and not wan_up(router1) and owned_inactive(router1), 30)
        end = time.monotonic() + 5
        while time.monotonic() < end:
            assert role(router1) == "fault", f"router1 is {role(router1)} after MASTER, FAULT"
            assert not wan_up(router1), "the WAN came up after FAULT"
            assert owned_inactive(router1), "owned units run after FAULT"
            time.sleep(0.5)
        # keepalived never left MASTER; replay it to restore the steady state.
        router1.succeed("""printf 'INSTANCE "main" MASTER 100\\n' > /run/router-ha/notify.fifo""")
        assert_steady(router1, [router2])

    with subtest("keepalived reload: the new reader keeps the MASTER's ownership"):
        # A reload replaces the FIFO reader; fifo_write_vrrp_states_on_reload
        # replays MASTER to it. Then demote by FIFO to prove the new reader
        # is listening, and restore.
        router1.succeed("systemctl reload keepalived")
        assert_steady(router1, [router2])
        router1.succeed("""printf 'INSTANCE "main" BACKUP 100\\n' > /run/router-ha/notify.fifo""")
        retry(lambda _: role(router1) == "backup" and not wan_up(router1), 30)
        router1.succeed("""printf 'INSTANCE "main" MASTER 100\\n' > /run/router-ha/notify.fifo""")
        assert_steady(router1, [router2])

    with subtest("keepalived reload mid-promotion: the new reader finishes it"):
        # keepalived does not replay MASTER after a reload. Simulate a
        # promotion killed between WAN down and WAN up.
        router1.succeed("touch /run/router-ha/master-pending && ip link set dev eth1 down")
        router1.succeed("systemctl reload keepalived")
        retry(lambda _: wan_up(router1), 30)
        router1.wait_until_fails("test -e /run/router-ha/master-pending", timeout=30)
        assert_steady(router1, [router2])

    with subtest("MASTER crash: router2 takes over, router1 returns after preemptDelay"):
        # keepalived has Restart=always: ExecStopPost demotes router1, the
        # restarted daemon comes back as BACKUP and must wait preemptDelay.
        router1.succeed("systemctl kill --signal=SIGKILL keepalived.service")
        t0 = time.monotonic()
        wait_role(router2, "master", timeout=30)
        print(f"router2 MASTER {time.monotonic() - t0:.1f} s after the crash")
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        assert_delayed_failback(router2, router1)

    with subtest("FAULT on LAN loss: router1 hands over, then returns after preemptDelay"):
        # GOTCHA: pull the cable (carrier loss), not `ip link set down`: the
        # RA owner's networkctl reload re-ups an admin-down link.
        router1.send_monitor_command("set_link vlan2 off")
        wait_role(router1, "fault", timeout=30)
        assert_steady(router2, [router1])
        router1.send_monitor_command("set_link vlan2 on")
        assert_delayed_failback(router2, router1)

    with subtest("MASTER reboot: router2 takes over, router1 boots as BACKUP"):
        router1.shutdown()
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        router1.start()
        router1.wait_for_unit("multi-user.target")
        # INVARIANT: ActivationPolicy=manual keeps the WAN down through boot.
        assert not wan_up(router1), "router1 raised its WAN while booting"
        keepalived_running(router1)
        assert_delayed_failback(router2, router1)

    with subtest("late LAN forwarding: the rebooted node waits for the peer, then preemptDelay"):
        # Stands in for a switch port still in spanning-tree learning: carrier
        # is up but router1 hears no adverts. Without the gate, keepalived's
        # master-down timer made router1 MASTER ~3 s after it started,
        # skipping preemptDelay.
        router1.shutdown()
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        router2.succeed("nft add table inet hidevrrp && nft add chain inet hidevrrp out '{ type filter hook output priority 0; }' && nft add rule inet hidevrrp out ip protocol vrrp drop")
        router1.start()
        router1.wait_for_unit("multi-user.target")
        router1.wait_until_succeeds("journalctl -b -u keepalived | grep -q 'Starting Keepalive'", timeout=60)
        # Well past the boot timer plus keepalived's master-down interval.
        end = time.monotonic() + PEER_WAIT - 5
        while time.monotonic() < end:
            assert role(router1) != "master", "router1 became MASTER while it could not hear router2"
            assert not has_vip(router1), "router1 took the VIP while it could not hear router2"
            time.sleep(0.5)
        router2.succeed("nft delete table inet hidevrrp")
        router1.wait_until_succeeds("journalctl -b -u keepalived | grep -q 'heard a VRRP advert'", timeout=30)
        keepalived_running(router1)
        assert_delayed_failback(router2, router1)

    with subtest("MASTER power loss: no final RA, the client's IPv6 follows router2"):
        # A crash sends no lifetime-0 RA. With per-node RA sources the client
        # kept the dead MASTER's route for its whole lifetime.
        client.wait_until_succeeds("ip -6 -o addr show dev eth1 scope global | grep -q 'inet6 2001:db8:'", timeout=60)
        router1.crash()
        t0 = time.monotonic()
        wait_role(router2, "master", timeout=30)
        router2.wait_until_succeeds("ip -6 -o addr show dev eth1 scope global | grep -q 2001:db8:1::", timeout=60)
        target = router2.succeed("ip -6 -o addr show dev eth1 scope global | grep 2001:db8:1:: | awk '{print $4}' | cut -d/ -f1 | head -1").strip()
        client.wait_until_succeeds(f"ping -6 -c1 -W1 {target}", timeout=20)
        print(f"client reaches router2's WAN over IPv6 {time.monotonic() - t0:.1f} s after the power loss")
        assert client_routers() == [VLL], f"client routers {client_routers()} after the power loss"
        assert client_router_mac() == lan_mac(router2), "the virtual router still resolves to the dead MASTER"
        router1.start()
        router1.wait_for_unit("multi-user.target")
        keepalived_running(router1)
        assert_delayed_failback(router2, router1)
  '';
}
