{
  self,
  lib,
  pkgs,
}:

# Two routers run Technitium with zoneReplication.ha: the VRRP MASTER holds
# home.example as Primary, the other node transfers it from the VIP as a
# Secondary. Records written on either owner must survive failover and
# fail-back, and at every steady state exactly one node holds the zone as
# Primary.
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };

  inherit (import ./lib/ha-pair.nix { inherit self; }) isp mkRouter;

  zone = "home.example";

  # Test-only secrets; real deployments use agenix or another secret store.
  # The TSIG secret is base64 of a fixed test string.
  zoneModule =
    { peer }:
    { pkgs, lib, ... }:
    {
      imports = [
        self.nixosModules.router-technitium
        # Minimal stand-in for agenix: router-technitium reads
        # age.secrets.<name>.path.
        {
          options.age.secrets = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule { options.path = lib.mkOption { type = lib.types.str; }; });
            default = { };
          };
        }
      ];

      virtualisation.memorySize = 2048;

      environment.etc = {
        "test-secrets/technitium-admin".text = "vm-test-admin";
        "test-secrets/zone-transfer".text = "dm0tdGVzdC16b25lLXRyYW5zZmVyLWtleQ==";
      };
      age.secrets.technitium-admin-password.path = "/etc/test-secrets/technitium-admin";

      # GOTCHA: resolved's stub listener holds port 53, which Technitium
      # needs on every address.
      services.resolved.enable = lib.mkForce false;

      services.router-technitium = {
        enable = true;
        bootstrapPasswordSecretName = "technitium-admin-password";
        enableBlockLists = false;
        zoneReplication = {
          tsigKeyFile = "/etc/test-secrets/zone-transfer";
          secondary = {
            zones = [ { name = zone; } ];
            primaryAddresses = [ "10.0.10.1" ];
          };
          ha = {
            enable = true;
            peers = [ peer ];
          };
        };
      };

      # Both nodes declare the same static records, as a pair built from one
      # configuration does.
      services.router.dnsZones.${zone} = {
        nameserverIP = "10.0.10.1";
        staticHosts.gw.ipAddress = "10.0.10.1";
      };

      environment.systemPackages = [
        pkgs.dnsutils
        pkgs.curl
        self.packages.${pkgs.stdenv.hostPlatform.system}.routerctl
      ];
    };
in
mkRouterTest {
  name = "router-technitium-zone-ha";

  nodes = {
    inherit isp;

    router1 = mkRouter {
      role = "master";
      lanAddress = "10.0.10.2/24";
      mgmtAddress = "192.168.100.2/24";
      extraModule = zoneModule { peer = "10.0.10.3"; };
    };

    router2 = mkRouter {
      role = "backup";
      lanAddress = "10.0.10.3/24";
      mgmtAddress = "192.168.100.3/24";
      extraModule = zoneModule { peer = "10.0.10.2"; };
    };
  };

  testScript = ''
    import json
    import time

    routers = [router1, router2]
    ZONE = "${zone}"
    TOKEN = "/var/lib/private/technitium-dns-server/nix-router-api-token"

    def api(r, path, **params):
        args = " ".join(f"--data-urlencode {k}={v}" for k, v in params.items())
        out = r.succeed(
            f"curl -fsS -G --data-urlencode token=$(cat {TOKEN}) {args} http://127.0.0.1:5380/api/{path}"
        )
        resp = json.loads(out)
        # Technitium reports errors with HTTP 200.
        assert resp.get("status") == "ok", f"{r.name} {path}: {resp}"
        return resp["response"]

    def zone_type(r):
        zones = api(r, "zones/list")["zones"]
        return next((z["type"] for z in zones if z["name"].lower() == ZONE), None)

    def role(r):
        return r.succeed("cat /run/router-ha/role 2>/dev/null || echo none").strip()

    def wait_owner(master, other, timeout=180):
        """Master holds the zone as Primary, the other as Secondary; then sample."""
        def check(_):
            t1, t2 = zone_type(master), zone_type(other)
            master.log(f"{master.name}={t1} {other.name}={t2}")
            return role(master) == "master" and t1 == "Primary" and t2 == "Secondary"
        retry(check, timeout)
        end = time.monotonic() + 5
        while time.monotonic() < end:
            types = {r.name: zone_type(r) for r in routers}
            assert list(types.values()).count("Primary") == 1, f"zone Primary on more than one node: {types}"
            time.sleep(1)

    def add_a(r, name, address):
        api(r, "zones/records/add", zone=ZONE, domain=f"{name}.{ZONE}", type="A", ipAddress=address, ttl=60)

    def dump(r):
        print(r.succeed(f"curl -sS -G --data-urlencode token=$(cat {TOKEN}) --data-urlencode zone={ZONE} http://127.0.0.1:5380/api/zones/options/get || true"))
        print(r.succeed(f"curl -sS -G --data-urlencode token=$(cat {TOKEN}) http://127.0.0.1:5380/api/zones/list || true"))
        print(r.succeed(f"dig @127.0.0.1 {ZONE} SOA +norec || true"))
        print(r.succeed(f"dig @10.0.10.1 {ZONE} AXFR || true"))
        print(r.succeed("journalctl --no-pager -u technitium-dns-server -u technitium-zone-replication -u technitium-zone-ha-owner | tail -60 || true"))
        print(r.succeed("ls -la /var/lib/private/technitium-dns-server/logs 2>/dev/null; tail -40 /var/lib/private/technitium-dns-server/logs/*.log 2>/dev/null || true"))

    def wait_resolves(r, name, address, timeout=60):
        try:
            r.wait_until_succeeds(f"dig +short @127.0.0.1 {name}.{ZONE} A | grep -qx {address}", timeout=timeout)
        except Exception:
            for x in routers:
                print(f"===== {x.name}")
                dump(x)
            raise

    start_all()
    isp.wait_for_unit("dnsmasq.service")
    for r in routers:
        r.wait_for_unit("technitium-bootstrap-api-token.service", timeout=300)
        r.wait_until_succeeds("systemctl is-active keepalived.service", timeout=60)

    with subtest("election: router1 holds the zone as Primary, router2 as Secondary"):
        wait_owner(router1, router2)

    def sync_runs(r):
        return int(r.succeed(
            "journalctl -b --no-pager -u technitium-sync-static-hosts | grep -c 'Static DNS records synchronized' || true"
        ).strip())

    with subtest("static records: the owner writes them, the backup skips its Secondary"):
        wait_resolves(router2, "gw", "10.0.10.1")
        router2.succeed("systemctl restart technitium-sync-static-hosts.service")
        router2.succeed("journalctl -b --no-pager -u technitium-sync-static-hosts | grep -q 'Skipping ${zone}'")
        assert zone_type(router2) == "Secondary"

    with subtest("routerctl: VRRP role and zone state per node, no secrets"):
        token = router1.succeed(f"cat {TOKEN}").strip()
        for r, want_role, want_type in [(router1, "master", "Primary"), (router2, "backup", "Secondary")]:
            raw = {c: r.succeed(f"routerctl {c} --json") for c in ("ha", "dns", "leases")}
            r_token = r.succeed(f"cat {TOKEN}").strip()
            for c, out in raw.items():
                assert token not in out and r_token not in out, f"routerctl {c} leaked the API token"
            ha, dns, leases = (json.loads(raw[c]) for c in ("ha", "dns", "leases"))
            v = ha["vrrp"]
            assert v["available"] and v["role"] == want_role and v["keepalived_active"], ha
            assert v["wan_health_pinned"] is False and isinstance(v["role_since"], int), ha
            assert not ha["kea_ha"]["available"], ha
            assert dns["available"], dns
            zone = next(z for z in dns["zones"] if z["name"].lower() == ZONE)
            assert zone["type"] == want_type, zone
            assert set(zone) == {"name", "type", "disabled", "soa_serial", "sync_failed", "notify_failed", "expired"}, zone
            assert not leases["available"] and leases["leases"] == [], leases

    with subtest("a record written on the owner reaches the secondary"):
        add_a(router1, "one", "10.0.10.51")
        wait_resolves(router2, "one", "10.0.10.51")

    with subtest("standby retries creating its Secondary until the primary answers"):
        # Same race as both nodes booting together: the standby asks before
        # the owner's Technitium answers SOA.
        router1.succeed("systemctl stop technitium-dns-server.service")
        api(router2, "zones/delete", zone=ZONE)
        router2.execute("systemctl restart technitium-zone-replication.service")
        router2.wait_until_succeeds(
            "[ $(systemctl show -P NRestarts technitium-zone-replication.service) -ge 1 ]", timeout=60
        )
        assert zone_type(router2) is None, "the Secondary cannot exist while no primary answers"
        router1.succeed("systemctl start technitium-dns-server.service")
        router1.wait_until_succeeds("curl -fsS http://127.0.0.1:5380/api/dns/status", timeout=180)
        wait_owner(router1, router2)
        wait_resolves(router2, "one", "10.0.10.51")

    with subtest("failover: router2 promotes, router1 demotes, data kept"):
        runs = sync_runs(router2)
        router1.succeed("systemctl stop keepalived.service")
        t0 = time.monotonic()
        wait_owner(router2, router1)
        print(f"zone ownership moved in {time.monotonic() - t0:.1f} s")
        # Promotion reruns the static sync, which now writes the zone.
        router2.wait_until_succeeds(
            f"[ $(journalctl -b --no-pager -u technitium-sync-static-hosts | grep -c 'Static DNS records synchronized') -gt {runs} ]",
            timeout=60,
        )
        router2.succeed("systemctl is-active technitium-sync-static-hosts.service")
        wait_resolves(router2, "one", "10.0.10.51")
        add_a(router2, "two", "10.0.10.52")
        wait_resolves(router1, "two", "10.0.10.52")

    with subtest("fail-back: router1 takes the zone back with both records"):
        router1.succeed("systemctl start keepalived.service")
        t0 = time.monotonic()
        wait_owner(router1, router2)
        print(f"zone ownership moved back in {time.monotonic() - t0:.1f} s")
        for name, address in [("one", "10.0.10.51"), ("two", "10.0.10.52")]:
            wait_resolves(router1, name, address)
            wait_resolves(router2, name, address)
  '';
}
