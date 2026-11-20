{
  self,
  lib,
  pkgs,
}:

# VRRP lifecycle on two routers with preemptDelay and a single-active unit:
# election, crash of the MASTER, delayed fail-back, FAULT on LAN loss, and a
# reboot of the MASTER. At every steady state exactly one node holds the
# VIP, the WAN link and the single-active unit, sampled for a few seconds.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp mkRouter;

  preemptDelay = 10;

  pairModule =
    { pkgs, ... }:
    {
      services.router-ha = {
        inherit preemptDelay;
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
  };

  testScript = ''
    import time

    routers = [router1, router2]
    PREEMPT_DELAY = ${toString preemptDelay}

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

    def owned_active(r):
        return r.execute("systemctl is-active --quiet ha-owned.service")[0] == 0

    def keepalived_running(r):
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    def assert_steady(master, others, hold=5):
        """Exactly one owner: wait for the handover to finish, then sample."""
        wait_role(master, "master")
        master.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)
        master.wait_until_succeeds("systemctl is-active --quiet ha-owned.service", timeout=30)
        for r in others:
            r.wait_until_succeeds("! systemctl is-active --quiet ha-owned.service", timeout=30)
            r.wait_until_succeeds("! ip -4 addr show dev eth1 | grep -q inet", timeout=30)
        end = time.monotonic() + hold
        while time.monotonic() < end:
            assert role(master) == "master", f"{master.name} lost MASTER"
            assert wan_up(master) and has_vip(master) and owned_active(master), f"{master.name} lost ownership"
            for r in others:
                assert role(r) in ("backup", "fault"), f"{r.name} is {role(r)} next to {master.name}"
                assert not wan_up(r), f"both {master.name} and {r.name} hold the WAN"
                assert not has_vip(r), f"both {master.name} and {r.name} hold the VIP"
                assert not owned_active(r), f"ha-owned runs on {r.name} and {master.name}"
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
            assert not owned_active(old_master), f"ha-owned runs on BACKUP {old_master.name}"
            time.sleep(0.5)
        wait_role(old_master, "master", timeout=PREEMPT_DELAY + 30)
        assert_steady(old_master, [new_master])

    start_all()
    isp.wait_for_unit("dnsmasq.service")
    isp.wait_for_unit("radvd.service")
    for r in routers:
        keepalived_running(r)

    with subtest("election: router1 (priority 100) owns VIP, WAN and the unit"):
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
        router1.succeed("ip link set dev eth2 down")
        wait_role(router1, "fault", timeout=30)
        assert_steady(router2, [router1])
        router1.succeed("ip link set dev eth2 up")
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
  '';
}
