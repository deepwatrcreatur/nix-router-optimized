{
  self,
  lib,
  pkgs,
}:

# router-apply: an unconfirmed change that breaks management access is
# reverted within the timeout; a confirmed change stays and becomes the boot
# default; `diff` shows the rendered change before applying it.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };
in
mkRouterTest {
  name = "router-apply";

  nodes = {
    router = { lib, pkgs, ... }: {
      imports = [ self.nixosModules.router-apply ];
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      services.openssh.enable = true;
      systemd.network.networks."10-mgmt" = {
        matchConfig.Name = "eth1";
        address = [ "192.168.1.1/24" ];
      };
      services.router-apply = {
        enable = true;
        defaultTimeoutSec = 30;
      };

      # The bad change: management moves to an address nobody uses.
      specialisation.broken.configuration = {
        systemd.network.networks."10-mgmt".address = lib.mkForce [ "192.168.1.99/24" ];
      };
      # A unit whose config file has no store references of its own: diff
      # must treat it as a leaf, not abort under errexit/pipefail.
      systemd.services.leaf = {
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/cat ${pkgs.writeText "leaf.conf" "setting=old\n"}";
      };
      # A harmless change to confirm.
      specialisation.good.configuration = {
        environment.etc."router-apply-marker".text = "good";
        systemd.services.leaf.serviceConfig.ExecStart = lib.mkForce
          "${pkgs.coreutils}/bin/cat ${pkgs.writeText "leaf.conf" "setting=new\n"}";
      };
      # An activation that hangs: activation scripts run synchronously in
      # switch-to-configuration (a oneshot unit would not block it).
      specialisation.hung.configuration = {
        system.activationScripts.hang = "${pkgs.coreutils}/bin/touch /run/hang-started; ${pkgs.coreutils}/bin/sleep 600";
      };
    };

    admin = { ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-mgmt" = {
        matchConfig.Name = "eth1";
        address = [ "192.168.1.2/24" ];
      };
    };
  };

  testScript = ''
    import time

    start_all()
    router.wait_for_unit("sshd.service")
    admin.wait_until_succeeds("nc -z -w 2 192.168.1.1 22", timeout=60)

    base = router.succeed("readlink -f /run/current-system").strip()
    broken = router.succeed("readlink -f /run/current-system/specialisation/broken").strip()
    good = router.succeed("readlink -f /run/current-system/specialisation/good").strip()
    hung = router.succeed("readlink -f /run/current-system/specialisation/hung").strip()
    profile_before = router.succeed("readlink -f /nix/var/nix/profiles/system || true").strip()

    with subtest("diff shows the rendered networkd change"):
        out = router.succeed(f"router-apply diff {broken}")
        print(out)
        assert "=== /etc/systemd/network" in out, out
        assert "+Address=192.168.1.99/24" in out and "-Address=192.168.1.1/24" in out, out
        assert "No change." in router.succeed(f"router-apply diff {base}")
        leaf = router.succeed(f"ROUTER_APPLY_DIFF_UNITS=leaf router-apply diff {good}")
        print(leaf)
        assert "=== leaf.service" in leaf and "+setting=new" in leaf and "-setting=old" in leaf, leaf

    with subtest("unconfirmed change that cuts management access is reverted"):
        router.succeed(f"router-apply switch --timeout 30 {broken}")
        t0 = time.monotonic()
        assert router.succeed("readlink -f /run/current-system").strip() == broken
        router.succeed("ip -4 addr show dev eth1 | grep -q 192.168.1.99/")
        admin.fail("nc -z -w 2 192.168.1.1 22")
        assert "reverts in" in router.succeed("router-apply status")
        # A second trial is refused while one is pending.
        router.fail(f"router-apply switch {good}")
        router.wait_until_succeeds(
            f"[ $(readlink -f /run/current-system) = {base} ]", timeout=90
        )
        took = time.monotonic() - t0
        print(f"reverted {took:.1f}s after the switch")
        assert 25 <= took <= 60, f"revert after {took:.1f}s, want about 30s"
        admin.wait_until_succeeds("nc -z -w 2 192.168.1.1 22", timeout=60)
        # /run/current-system flips before the revert unit finishes cleaning up.
        router.wait_until_succeeds("router-apply status | grep -q 'No trial pending'", timeout=30)
        assert router.succeed("readlink -f /nix/var/nix/profiles/system || true").strip() == profile_before, \
            "an unconfirmed trial must never move the boot default"
        router.succeed("journalctl -t router-apply | grep -q 'not confirmed in time'")

    with subtest("manual revert ends a trial at once"):
        router.succeed(f"router-apply switch --timeout 600 {good}")
        router.succeed("test -e /etc/router-apply-marker")
        router.succeed("router-apply revert")
        assert router.succeed("readlink -f /run/current-system").strip() == base
        router.fail("test -e /etc/router-apply-marker")
        router.fail("systemctl is-active router-apply-revert.timer")

    with subtest("hung activation: confirm is refused, the timer stops it and reverts"):
        router.succeed(f"(router-apply switch --timeout 20 {hung} >/tmp/hung.log 2>&1 &)")
        router.wait_until_succeeds("systemctl show -P ActiveState router-apply-trial.service | grep -qx activating", timeout=30)
        router.wait_until_succeeds("test -e /run/hang-started", timeout=30)
        out = router.fail("router-apply confirm 2>&1")
        assert "still running" in out, out
        router.succeed("systemctl is-active router-apply-revert.timer")
        router.wait_until_succeeds("router-apply status | grep -q 'No trial pending'", timeout=90)
        assert router.succeed("readlink -f /run/current-system").strip() == base
        router.fail("systemctl show -P ActiveState router-apply-trial.service | grep -qE '^(active|activating)$'")
        router.fail("pgrep -f 'sleep 600'")
        admin.wait_until_succeeds("nc -z -w 2 192.168.1.1 22", timeout=60)

    with subtest("confirmed change stays and becomes the boot default"):
        router.succeed(f"router-apply switch --timeout 30 {good}")
        router.succeed("router-apply confirm")
        router.fail("systemctl is-active router-apply-revert.timer")
        time.sleep(40)
        assert router.succeed("readlink -f /run/current-system").strip() == good
        router.succeed("grep -qx good /etc/router-apply-marker")
        assert router.succeed("readlink -f /nix/var/nix/profiles/system").strip() == good
        router.fail("router-apply confirm")
  '';
}
