{
  self,
  lib,
  pkgs,
  nixpkgs,
  system,
  eval,
}:

let
  alertingModule = {
    services.kea.dhcp4 = {
      enable = true;
      settings = {
        interfaces-config.interfaces = [ "lo" ];
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        subnet4 = [
          {
            id = 1;
            subnet = "10.99.0.0/24";
            pools = [ { pool = "10.99.0.100 - 10.99.0.200"; } ];
          }
        ];
      };
    };
    services.prometheus.enable = true;
    services.router-alerting = {
      enable = true;
      ntfy = {
        enable = true;
        urlFile = "/run/secrets/ntfy-url";
      };
      email = {
        enable = true;
        to = "ops@example.org";
        from = "router@example.org";
        smarthost = "smtp.example.org:587";
        username = "router";
        passwordFile = "/run/secrets/smtp";
      };
      watchdog.pingUrlFile = "/run/secrets/hc";
      newDhcpDevices.enable = true;
    };
  };
  cfg =
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {
          networking.hostName = "router-check";
          system.stateVersion = "25.11";
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.devices = [ "nodev" ];
        }
        self.nixosModules.router-alerting
        alertingModule
      ];
    }).config;
  am = cfg.services.prometheus.alertmanager.configuration;
  hook = lib.findFirst (h: lib.hasSuffix "libdhcp_run_script.so" h.library) null cfg.services.kea.dhcp4.settings.hooks-libraries;
  bridge = lib.head (lib.splitString " " cfg.systemd.services.router-alerting-ntfy.serviceConfig.ExecStart);
  amConfig = pkgs.writeText "alertmanager.json" (builtins.toJSON am);
  keaConfig = pkgs.writeText "kea-dhcp4.json" (builtins.toJSON { Dhcp4 = cfg.services.kea.dhcp4.settings; });
in
{
  router-alerting-eval = eval.mkNixosEvalCheck "router-alerting" [
    self.nixosModules.router-alerting
    alertingModule
    ({ config, ... }: {
      assertions = [
        {
          assertion =
            config.services.prometheus.alertmanagers != [ ]
            && config.services.prometheus.alertmanager.listenAddress == "127.0.0.1"
            && config.services.prometheus.globalConfig.external_labels.host == "router-check";
          message = "Prometheus must send to a loopback-only Alertmanager.";
        }
        {
          assertion = lib.all (c: lib.elem c config.systemd.services.alertmanager.serviceConfig.LoadCredential) [
            "email-password:/run/secrets/smtp"
            "watchdog-url:/run/secrets/hc"
          ];
          message = "secrets reach the DynamicUser Alertmanager as credentials.";
        }
        {
          assertion = config.systemd.services.kea-dhcp4-server.environment ? KEA_HOOK_SCRIPTS_PATH;
          message = "Kea 3 needs KEA_HOOK_SCRIPTS_PATH for the run_script hook.";
        }
      ];
    })
  ];

  router-alerting-missing-receiver-fails-eval = eval.mkNixosEvalFailureCheck "router-alerting-missing-receiver" [
    self.nixosModules.router-alerting
    { services.router-alerting.enable = true; }
  ];

  # Exercises the generated configs and scripts, not just their evaluation.
  router-alerting-runtime = pkgs.runCommand "router-alerting-runtime" {
    nativeBuildInputs = [ pkgs.prometheus-alertmanager pkgs.kea pkgs.python3 pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnugrep ];
  } ''
    set -euo pipefail
    echo "== amtool"
    amtool check-config ${amConfig}

    echo "== kea-dhcp4 starts with the hook (kea -t does not load hooks)"
    # GOTCHA: Kea 3 refuses hook scripts outside KEA_HOOK_SCRIPTS_PATH; only
    # a real start proves the module's environment setting is right.
    jq '.Dhcp4["interfaces-config"]["dhcp-socket-type"] = "udp"
        | .Dhcp4["lease-database"] = {type: "memfile", persist: false}' ${keaConfig} > kea.json
    env KEA_PIDFILE_DIR=$PWD KEA_LOCKFILE_DIR=$PWD \
      KEA_HOOK_SCRIPTS_PATH=${cfg.systemd.services.kea-dhcp4-server.environment.KEA_HOOK_SCRIPTS_PATH} \
      kea-dhcp4 -p 10067 -c kea.json > kea.log 2>&1 & K=$!
    sleep 3
    kill -0 $K || { cat kea.log; echo "kea failed to start with the hook"; exit 1; }
    grep -q RUN_SCRIPT_LOAD kea.log
    kill $K

    echo "== ntfy bridge"
    mkdir -p creds; echo "http://127.0.0.1:18081/topic" > creds/ntfy-url
    cat > fake.py <<'PY'
    import json, sys
    from http.server import BaseHTTPRequestHandler, HTTPServer
    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"])).decode()
            with open(sys.argv[2], "a") as f:
                f.write(json.dumps({"path": self.path, "title": self.headers.get("Title"),
                                    "priority": self.headers.get("Priority"), "body": body}) + "\n")
            self.send_response(200); self.end_headers()
        def log_message(self, *a): pass
    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
    PY
    python3 fake.py 18081 ntfy.log & F1=$!
    CREDENTIALS_DIRECTORY=$PWD/creds ${bridge} 18082 & B=$!
    for i in $(seq 50); do curl -s -o /dev/null http://127.0.0.1:18082/ -d '{}' && break; sleep 0.1; done
    curl -fsS http://127.0.0.1:18082/ -d '{"status":"firing","alerts":[{"status":"firing","labels":{"alertname":"RouterNicCarrierLost","severity":"critical","instance":"localhost:9100","host":"r1"},"annotations":{"summary":"lan0 has no carrier"}}]}'
    jq -e 'select(.title == "RouterNicCarrierLost on r1" and .priority == "5" and .body == "lan0 has no carrier")' ntfy.log >/dev/null

    echo "== new-device hook"
    python3 fake.py 18093 am.log & F2=$!
    sleep 0.5
    printf 'address,hwaddr,client_id\n10.99.0.101,aa:bb:cc:00:00:01,\n' > leases
    printf 'address,hwaddr,client_id\n10.99.0.104,aa:bb:cc:00:00:04,\n' > leases.2
    script=$(mktemp); sed -e "s|/var/lib/kea/dhcp4.leases|$PWD/leases|; s|/var/lib/kea/router-alerting-seen-macs|$PWD/seen|; s|127.0.0.1:9093|127.0.0.1:18093|" ${hook.parameters.name} > $script; chmod +x $script
    # GOTCHA: run like Kea does, with no inherited environment.
    env -i LEASES4_SIZE=1 LEASES4_AT0_HWADDR=aa:bb:cc:00:00:02 LEASES4_AT0_ADDRESS=10.99.0.102 $script leases4_committed
    test ! -e am.log || { echo "first run must only seed"; exit 1; }
    grep -qx aa:bb:cc:00:00:01 seen && grep -qx aa:bb:cc:00:00:02 seen && grep -qx aa:bb:cc:00:00:04 seen
    # A send that fails (Alertmanager down) must not mark the device known.
    kill $F2; sleep 0.3
    env -i LEASES4_SIZE=1 LEASES4_AT0_HWADDR=AA:BB:CC:00:00:03 LEASES4_AT0_ADDRESS=10.99.0.103 LEASES4_AT0_HOSTNAME=phone. $script leases4_committed || true
    ! grep -qx aa:bb:cc:00:00:03 seen
    python3 fake.py 18093 am.log & F2=$!
    sleep 0.5
    env -i LEASE4_HWADDR=aa:bb:cc:00:00:03 LEASE4_ADDRESS=10.99.0.103 LEASE4_HOSTNAME=phone. $script lease4_renew
    env -i LEASE4_HWADDR=aa:bb:cc:00:00:03 LEASE4_ADDRESS=10.99.0.103 $script lease4_renew
    test "$(wc -l < am.log)" = 1
    jq -e '.path == "/api/v2/alerts" and (.body | fromjson | .[0].labels.mac == "aa:bb:cc:00:00:03" and (.[0].annotations.summary | contains("phone (aa:bb:cc:00:00:03)")))' am.log >/dev/null
    kill $F1 $F2 $B
    touch $out
  '';
}
