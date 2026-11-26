{
  self,
  lib,
  pkgs,
}:

# router-security-hardened kernelHardening on a booted kernel: sysctls are
# applied, and a blocked protocol module refuses an explicit modprobe and a
# socket() that would otherwise autoload it; with denyExplicitLoad off the
# same modprobe works. A live switch from loose to strict reaches interfaces
# that already have addresses.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };
in
mkRouterTest {
  name = "router-security-hardened";

  nodes.router = { ... }: {
    imports = [ self.nixosModules.router-security-hardened ];
    environment.systemPackages = [ pkgs.python3 ];
    services.router-security-hardened = {
      enable = true;
      kernelHardening = {
        enable = true;
        rpFilter = "loose";
      };
    };
    # Live switch target for the rp_filter regression below.
    specialisation.strict.configuration.services.router-security-hardened.kernelHardening.rpFilter =
      lib.mkForce "strict";
  };

  # Control: blacklist only. Explicit modprobe must work here, so the router
  # node's refusal comes from the install line.
  nodes.blacklistOnly = { ... }: {
    imports = [ self.nixosModules.router-security-hardened ];
    services.router-security-hardened = {
      enable = true;
      kernelHardening = {
        enable = true;
        denyExplicitLoad = false;
      };
    };
  };

  testScript = ''
    start_all()
    router.wait_for_unit("multi-user.target")
    router.succeed("test \"$(sysctl -n net.ipv4.conf.all.rp_filter)\" = 2")
    router.succeed("test \"$(sysctl -n kernel.kptr_restrict)\" = 2")
    router.succeed("test \"$(sysctl -n net.core.bpf_jit_harden)\" = 2")
    router.succeed("test \"$(sysctl -n fs.suid_dumpable)\" = 0")
    # Live loose -> strict: an addressed interface keeps its own value (Linux
    # stops copying `default` once it has an address) and the kernel uses the
    # higher of `all` and the interface. Simulate the inherited loose value,
    # switch without reboot, and require the interface not to override `all`.
    router.succeed("ip -4 addr show dev eth1 | grep -q inet")
    router.succeed("sysctl -w net.ipv4.conf.eth1.rp_filter=2")
    router.succeed("/run/current-system/specialisation/strict/bin/switch-to-configuration test")
    router.succeed("test \"$(sysctl -n net.ipv4.conf.all.rp_filter)\" = 1")
    router.succeed("test \"$(sysctl -n net.ipv4.conf.eth1.rp_filter)\" = 0")
    # INVARIANT: the module exists in this kernel, or the checks below prove
    # nothing (DCCP, for one, left Linux in 6.16). modinfo ignores install lines.
    router.succeed("modinfo -F filename tipc")
    # Explicit load by name: refused by the install line, not just the blacklist.
    router.fail("modprobe tipc")
    # Autoload through socket(AF_TIPC, SOCK_RDM) must not load it either.
    router.succeed("python3 -c 'import socket; socket.socket(30, socket.SOCK_RDM)' || true")
    router.fail("grep -qw '^tipc' /proc/modules")

    blacklistOnly.wait_for_unit("multi-user.target")
    blacklistOnly.succeed("modprobe tipc")
    blacklistOnly.succeed("grep -qw '^tipc' /proc/modules")
  '';
}
