{
  self,
  lib,
  pkgs,
}:

# router.monitoring.hardwareSensors data path: the timer runs the collector,
# node_exporter (a DynamicUser) can read the textfile directory, and the
# metric reaches Prometheus. The VM has no mlx5 NIC or SFPs, so it checks
# the collector heartbeat; real readings were verified on elitedesk's
# ConnectX-4 Lx (see docs/router-hardware-monitoring.md).
let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };
in
mkRouterTest {
  name = "router-hw-sensors";

  nodes.router = { ... }: {
    imports = [ self.nixosModules.monitoring ];
    virtualisation.memorySize = 2048;
    router.monitoring = {
      enable = true;
      hardwareSensors.enable = true;
    };
  };

  testScript = ''
    router.wait_for_unit("prometheus-node-exporter.service")
    router.wait_until_succeeds("test -s /run/router-hw-sensors/router_hardware.prom", timeout=120)
    router.succeed("stat -c %a /run/router-hw-sensors/router_hardware.prom | grep -qx 644")
    router.wait_until_succeeds(
        "curl -fsS localhost:9100/metrics | grep -q '^router_hw_sensors_last_run_timestamp_seconds '",
        timeout=60,
    )
    router.wait_for_unit("prometheus.service")
    router.wait_until_succeeds(
        "curl -fsS 'localhost:9090/api/v1/query?query=router_hw_sensors_last_run_timestamp_seconds'"
        " | grep -q '\"result\":\\[{'",
        timeout=120,
    )
    router.succeed("test -s /etc/grafana-dashboards/router-hardware.json")
  '';
}
