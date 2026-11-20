{
  self,
  lib,
  pkgs,
}:

# WAN health tracking (services.router-ha.wan.healthCheck) on two routers
# with preemptDelay: the master's upstream goes dark while carrier stays up,
# the peer takes VIP and WAN within seconds (not after preemptDelay), the
# pinned node does not preempt back until retryAfterSec, and an ISP outage
# that affects both nodes leaves exactly one stable master instead of none.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp mkRouter;

  preemptDelay = 10;
  retryAfterSec = 45;
  startupGraceSec = 10;

  healthModule = {
    services.router-ha = {
      inherit preemptDelay;
      wan.healthCheck = {
        enable = true;
        inherit retryAfterSec startupGraceSec;
      };
    };
    boot.kernelModules = [ "sch_netem" ];
  };
in
mkRouterTest {
  name = "router-ha-wan-health";

  nodes = {
    isp = { ... }: {
      imports = [ isp ];
      boot.kernelModules = [ "sch_netem" ];
    };

    router1 = mkRouter {
      role = "master";
      lanAddress = "10.0.10.2/24";
      mgmtAddress = "192.168.100.2/24";
      extraModule = healthModule;
    };

    router2 = mkRouter {
      role = "backup";
      lanAddress = "10.0.10.3/24";
      mgmtAddress = "192.168.100.3/24";
      extraModule = healthModule;
    };
  };

  testScript = ''
    import time

    routers = [router1, router2]
    PREEMPT_DELAY = ${toString preemptDelay}
    RETRY = ${toString retryAfterSec}

    def role(r):
        return r.succeed("cat /run/router-ha/role").strip()

    def penalty(r):
        return r.succeed("cat /run/router-ha/wan-penalty 2>/dev/null || echo 0").strip()

    def wait_role(r, want, timeout=60):
        r.wait_until_succeeds(f"grep -qx {want} /run/router-ha/role", timeout=timeout)

    def wait_wan_lease(r):
        r.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 198.51.100.50/'", timeout=60)

    def has_vip(r):
        return r.execute("ip -4 addr show dev eth2 | grep -q 'inet 10.0.10.1/'")[0] == 0

    def time_until_master(r, timeout):
        start = time.monotonic()
        while time.monotonic() - start < timeout:
            if role(r) == "master":
                return time.monotonic() - start
            time.sleep(0.2)
        raise AssertionError(f"{r.name} not master within {timeout}s")

    def assert_steady(master, backup, seconds):
        for _ in range(seconds):
            assert role(master) == "master", f"{master.name} lost master"
            assert role(backup) != "master", f"{backup.name} became master"
            assert has_vip(master) and not has_vip(backup), "VIP must be on exactly one node"
            time.sleep(1)

    def dark(node, on):
        if on:
            node.succeed("tc qdisc replace dev eth1 root netem loss 100%")
        else:
            node.succeed("tc qdisc del dev eth1 root")

    start_all()
    isp.wait_for_unit("dnsmasq.service")
    for r in routers:
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    with subtest("election: router1 master with a healthy WAN"):
        wait_role(router1, "master", timeout=90)
        wait_role(router2, "backup")
        wait_wan_lease(router1)
        # Past the startup grace the check runs and passes.
        time.sleep(${toString startupGraceSec} + 3)
        assert role(router1) == "master"
        assert penalty(router1) == "0"

    with subtest("dark upstream with carrier up: router2 takes over fast"):
        dark(router1, True)
        router1.succeed("ip link show dev eth1 | grep -q 'state UP'")
        took = time_until_master(router2, 15)
        print(f"router2 master {took:.1f}s after router1's upstream went dark")
        assert took <= 5, f"takeover took {took:.1f}s, want <= 5s (preemptDelay {PREEMPT_DELAY}s must not apply)"
        wait_wan_lease(router2)
        router1.wait_until_succeeds("grep -qx 1 /run/router-ha/wan-penalty", timeout=5)
        router1.wait_until_succeeds("journalctl -t router-ha | grep -q 'yielding to the peer'", timeout=10)

    with subtest("pinned router1 stays backup past preemptDelay"):
        assert_steady(router2, router1, PREEMPT_DELAY + 5)

    with subtest("retry: router1 preempts after retryAfterSec + preemptDelay and stays"):
        dark(router1, False)
        pinned_since = int(router1.succeed("stat -c %Y /run/router-ha/wan-penalty").strip())
        wait_role(router1, "master", timeout=RETRY + PREEMPT_DELAY + 30)
        became = int(router1.succeed("stat -c %Y /run/router-ha/role").strip())
        waited = became - pinned_since
        print(f"router1 retook master {waited}s after its pin")
        assert waited >= RETRY + PREEMPT_DELAY - 1, f"fail-back after {waited}s ignores retry/preemptDelay"
        wait_role(router2, "backup")
        wait_wan_lease(router1)
        time.sleep(${toString startupGraceSec} + 3)
        assert penalty(router1) == "0", "a healthy master clears its pin"
        assert_steady(router1, router2, 5)

    with subtest("ISP outage on both: exactly one stable master, never none"):
        dark(isp, True)
        # router1 yields, router2 takes over, finds its WAN bad too and yields
        # back; router1 is already pinned and stays master.
        router2.wait_until_succeeds("grep -qx 1 /run/router-ha/wan-penalty", timeout=60)
        wait_role(router1, "master", timeout=30)
        router1.wait_until_succeeds("grep -qx 1 /run/router-ha/wan-penalty", timeout=5)
        # Shorter than router2's retry, so no further moves are expected.
        assert_steady(router1, router2, ${toString startupGraceSec} + 10)

    with subtest("ISP returns: router1 clears its pin while master"):
        dark(isp, False)
        router1.wait_until_succeeds("! grep -qx 1 /run/router-ha/wan-penalty", timeout=30)
        assert role(router1) == "master"
  '';
}
