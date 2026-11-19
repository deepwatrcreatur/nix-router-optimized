{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-alerting;
  amAddress = "127.0.0.1:${toString cfg.alertmanagerPort}";
  credDir = "/run/credentials/alertmanager.service";

  ntfyBridge = pkgs.writers.writePython3 "router-alerting-ntfy" { flakeIgnore = [ "E501" ]; } ''
    """Relay Alertmanager webhooks to ntfy (stdlib only)."""
    import json
    import os
    import sys
    import urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer

    CRED = os.environ["CREDENTIALS_DIRECTORY"]
    PRIORITY = {"critical": "5", "warning": "4", "info": "3"}


    def read(name):
        path = os.path.join(CRED, name)
        if not os.path.exists(path):
            return None
        with open(path) as f:
            return f.read().strip()


    URL = read("ntfy-url")
    TOKEN = read("ntfy-token")


    def publish(alert, status):
        labels = alert.get("labels", {})
        notes = alert.get("annotations", {})
        name = labels.get("alertname", "alert")
        severity = labels.get("severity", "warning")
        host = labels.get("instance") or labels.get("hostname") or ""
        title = ("Resolved: " if status == "resolved" else "") + name + (f" on {host}" if host else "")
        body = notes.get("summary") or notes.get("description") or name
        if notes.get("description") and notes.get("summary"):
            body += "\n" + notes["description"]
        headers = {
            "Title": title.encode("utf-8").decode("latin-1", "replace"),
            "Priority": "2" if status == "resolved" else PRIORITY.get(severity, "3"),
            "Tags": "white_check_mark" if status == "resolved" else ("rotating_light" if severity == "critical" else "warning"),
        }
        if TOKEN:
            headers["Authorization"] = "Bearer " + TOKEN
        req = urllib.request.Request(URL, data=body.encode("utf-8"), headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()


    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length) or b"{}")
                for alert in payload.get("alerts", []):
                    publish(alert, alert.get("status", payload.get("status", "firing")))
                self.send_response(200)
            except Exception as exc:  # Alertmanager retries on non-2xx
                print(f"ntfy relay failed: {exc}", file=sys.stderr, flush=True)
                self.send_response(502)
            self.end_headers()

        def log_message(self, fmt, *args):
            pass


    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
  '';

  # Kea's run_script hook calls this for every committed or renewed lease.
  newDeviceScripts = pkgs.runCommand "router-alerting-kea-scripts" { } ''
    mkdir -p $out
    cat > $out/new-device.sh <<'EOF'
    #!${pkgs.bash}/bin/bash
    # GOTCHA: Kea spawns hook scripts with only its LEASE*/QUERY* variables
    # and no PATH, so every tool below is called by absolute path.
    set -u
    case "''${1:-}" in
      leases4_committed)
        [ "''${LEASES4_SIZE:-0}" -gt 0 ] || exit 0
        mac="''${LEASES4_AT0_HWADDR:-}"; ip="''${LEASES4_AT0_ADDRESS:-}"; name="''${LEASES4_AT0_HOSTNAME:-}" ;;
      lease4_renew)
        mac="''${LEASE4_HWADDR:-}"; ip="''${LEASE4_ADDRESS:-}"; name="''${LEASE4_HOSTNAME:-}" ;;
      *) exit 0 ;;
    esac
    [ -n "$mac" ] || exit 0
    mac="''${mac,,}"
    seen=${escapeShellArg cfg.newDhcpDevices.seenFile}
    exec 9>>"$seen.lock"
    ${pkgs.util-linux}/bin/flock 9
    if [ ! -e "$seen" ]; then
      # WHY: on first use, every device with a lease is already known; seed
      # from the memfile, including Kea's compaction pieces (.1, .2,
      # .completed), instead of announcing the whole network.
      lf=${escapeShellArg cfg.newDhcpDevices.leaseFile}
      for f in "$lf" "$lf.1" "$lf.2" "$lf.completed"; do
        [ -r "$f" ] && ${pkgs.gawk}/bin/awk -F, 'FNR > 1 && $2 != "" { print tolower($2) }' "$f"
      done | ${pkgs.coreutils}/bin/sort -u > "$seen.tmp"
      ${pkgs.gnugrep}/bin/grep -qxF "$mac" "$seen.tmp" || printf '%s\n' "$mac" >> "$seen.tmp"
      ${pkgs.coreutils}/bin/mv "$seen.tmp" "$seen"
      exit 0
    fi
    ${pkgs.gnugrep}/bin/grep -qxF "$mac" "$seen" && exit 0
    now=$(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
    ends=$(${pkgs.coreutils}/bin/date -u -d '+${toString cfg.newDhcpDevices.alertMinutes} minutes' +%Y-%m-%dT%H:%M:%SZ)
    ${pkgs.jq}/bin/jq -n --arg mac "$mac" --arg ip "$ip" --arg name "''${name%.}" --arg host "$(${pkgs.hostname}/bin/hostname)" \
      --arg now "$now" --arg ends "$ends" \
      '[{labels: {alertname: "RouterNewDhcpDevice", severity: "info", mac: $mac, instance: $host},
         annotations: {summary: ("New device " + (if $name == "" then $mac else $name + " (" + $mac + ")" end) + " got " + $ip)},
         startsAt: $now, endsAt: $ends}]' \
      | ${pkgs.curl}/bin/curl -fsS -m 5 -H 'Content-Type: application/json' --data-binary @- \
          http://${amAddress}/api/v2/alerts >/dev/null || exit 1
    # WHY: remember the device only once Alertmanager accepted the alert, so
    # a failed send is retried on the next lease event.
    printf '%s\n' "$mac" >> "$seen"
    EOF
    chmod +x $out/new-device.sh
  '';

  receiverConfig =
    optionalAttrs cfg.email.enable {
      email_configs = [
        ({
          inherit (cfg.email) to from smarthost;
          send_resolved = true;
        }
        // optionalAttrs (cfg.email.username != null) { auth_username = cfg.email.username; }
        // optionalAttrs (cfg.email.passwordFile != null) { auth_password_file = "${credDir}/email-password"; })
      ];
    }
    // {
      webhook_configs =
        optional cfg.ntfy.enable {
          url = "http://127.0.0.1:${toString cfg.ntfy.bridgePort}/";
          send_resolved = true;
        }
        ++ cfg.extraWebhooks;
    }
    // cfg.extraReceiverConfig;

  watchdogRules = pkgs.writeText "router-alerting-watchdog.rules.json" (builtins.toJSON {
    groups = [
      {
        name = "router-alerting";
        rules = [
          {
            alert = "Watchdog";
            expr = "vector(1)";
            labels.severity = "none";
            annotations.summary = "Always firing; proves the alert path to the dead-man switch works.";
          }
        ];
      }
    ];
  });
in
{
  options.services.router-alerting = {
    enable = mkEnableOption ''
      router alert delivery: Alertmanager behind the router's Prometheus, with
      ntfy, email, webhook and a dead-man watchdog'';

    alertmanagerPort = mkOption {
      type = types.port;
      default = 9093;
      description = "Port Alertmanager listens on (127.0.0.1 only).";
    };

    clusterPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.10.4:9094" ];
      description = ''
        Other routers' Alertmanager cluster addresses (`host:9094`). Clustered
        nodes deduplicate notifications, so whichever router survives still
        sends them. Empty disables clustering.
      '';
    };

    ntfy = {
      enable = mkEnableOption "notifications through ntfy";
      urlFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File holding the full topic URL, for example `https://ntfy.sh/<topic>`.";
      };
      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file holding an ntfy access token (Bearer).";
      };
      bridgePort = mkOption {
        type = types.port;
        default = 9095;
        description = "Local port of the Alertmanager-to-ntfy relay.";
      };
    };

    email = {
      enable = mkEnableOption "notifications by email";
      to = mkOption {
        type = types.str;
        default = "";
        description = "Recipient address.";
      };
      from = mkOption {
        type = types.str;
        default = "";
        description = "Sender address.";
      };
      smarthost = mkOption {
        type = types.str;
        default = "";
        example = "smtp.example.com:587";
        description = "SMTP server as `host:port`; STARTTLS is required by default.";
      };
      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP username.";
      };
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File holding the SMTP password.";
      };
    };

    extraWebhooks = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      example = literalExpression ''[ { url = "http://127.0.0.1:8080/hook"; send_resolved = true; } ]'';
      description = "Additional Alertmanager `webhook_configs` entries for the default receiver.";
    };

    extraReceiverConfig = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''{ telegram_configs = [ { bot_token_file = "/run/credentials/alertmanager.service/tg"; chat_id = 123; } ]; }'';
      description = ''
        Any other native Alertmanager receiver configs (Telegram, Discord,
        Pushover, Slack, ...) merged into the default receiver. Secrets go in
        `extraCredentials` and are read from `${credDir}/<name>`.
      '';
    };

    extraCredentials = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = "Extra files loaded as systemd credentials for Alertmanager, by name.";
    };

    watchdog = {
      pingUrlFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          File holding a dead-man-switch URL (for example a healthchecks.io
          ping URL). An always-firing Watchdog alert is sent there every
          `watchdog.interval`; the external service alerts when pings stop,
          which also covers the router or its uplink being down.
        '';
      };
      interval = mkOption {
        type = types.str;
        default = "5m";
        description = "How often the watchdog pings.";
      };
    };

    newDhcpDevices = {
      enable = mkEnableOption ''
        a notification the first time a device (by MAC) gets a DHCP lease from
        Kea. The first run records every current lease as known'';
      leaseFile = mkOption {
        type = types.str;
        default = "/var/lib/kea/dhcp4.leases";
        description = "Kea memfile lease file used to seed known devices on first run.";
      };
      seenFile = mkOption {
        type = types.str;
        default = "/var/lib/kea/router-alerting-seen-macs";
        description = "Where known MAC addresses are kept (must be writable by Kea).";
      };
      alertMinutes = mkOption {
        type = types.ints.positive;
        default = 60;
        description = "How long a new-device alert stays active before it expires.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.ntfy.enable || cfg.email.enable || cfg.extraWebhooks != [ ] || cfg.extraReceiverConfig != { };
          message = "services.router-alerting needs at least one receiver (ntfy, email, extraWebhooks or extraReceiverConfig).";
        }
        {
          assertion = !cfg.ntfy.enable || cfg.ntfy.urlFile != null;
          message = "services.router-alerting.ntfy.urlFile must be set.";
        }
        {
          assertion = !cfg.email.enable || (cfg.email.to != "" && cfg.email.from != "" && cfg.email.smarthost != "");
          message = "services.router-alerting.email needs to, from and smarthost.";
        }
        {
          assertion = !cfg.newDhcpDevices.enable || config.services.kea.dhcp4.enable;
          message = "services.router-alerting.newDhcpDevices needs Kea DHCPv4 on this node.";
        }
      ];

      services.prometheus = {
        alertmanagers = [ { static_configs = [ { targets = [ amAddress ]; } ]; } ];
        ruleFiles = optional (cfg.watchdog.pingUrlFile != null) watchdogRules;
        alertmanager = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = cfg.alertmanagerPort;
          extraFlags =
            if cfg.clusterPeers == [ ] then [ "--cluster.listen-address=" ] else map (p: "--cluster.peer=${p}") cfg.clusterPeers;
          configuration = {
            route = {
              receiver = "default";
              group_by = [ "alertname" "instance" ];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "12h";
              routes =
                optional (cfg.watchdog.pingUrlFile != null) {
                  matchers = [ ''alertname="Watchdog"'' ];
                  receiver = "watchdog";
                  group_wait = "0s";
                  group_interval = cfg.watchdog.interval;
                  repeat_interval = cfg.watchdog.interval;
                }
                ++ [
                  {
                    # WHY: one notification per device; the alert expires by itself.
                    matchers = [ ''alertname="RouterNewDhcpDevice"'' ];
                    receiver = "default";
                    group_by = [ "mac" ];
                    group_wait = "10s";
                    repeat_interval = "8760h";
                  }
                ];
            };
            receivers = [
              ({ name = "default"; } // receiverConfig)
            ]
            ++ optional (cfg.watchdog.pingUrlFile != null) {
              name = "watchdog";
              webhook_configs = [
                {
                  url_file = "${credDir}/watchdog-url";
                  send_resolved = false;
                }
              ];
            };
          };
        };
      };

      # SECURITY: Alertmanager runs with DynamicUser; secrets reach it as
      # systemd credentials instead of world-readable paths.
      systemd.services.alertmanager.serviceConfig.LoadCredential =
        optional (cfg.email.enable && cfg.email.passwordFile != null) "email-password:${cfg.email.passwordFile}"
        ++ optional (cfg.watchdog.pingUrlFile != null) "watchdog-url:${cfg.watchdog.pingUrlFile}"
        ++ mapAttrsToList (name: file: "${name}:${file}") cfg.extraCredentials;
    }

    (mkIf cfg.ntfy.enable {
      systemd.services.router-alerting-ntfy = {
        description = "Relay Alertmanager notifications to ntfy";
        wantedBy = [ "multi-user.target" ];
        before = [ "alertmanager.service" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${ntfyBridge} ${toString cfg.ntfy.bridgePort}";
          DynamicUser = true;
          LoadCredential = [ "ntfy-url:${cfg.ntfy.urlFile}" ] ++ optional (cfg.ntfy.tokenFile != null) "ntfy-token:${cfg.ntfy.tokenFile}";
          Restart = "on-failure";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        };
      };
    })

    (mkIf cfg.newDhcpDevices.enable {
      services.kea.dhcp4.settings.hooks-libraries = [
        {
          library = "${config.services.kea.package or pkgs.kea}/lib/kea/hooks/libdhcp_run_script.so";
          parameters = {
            name = "${newDeviceScripts}/new-device.sh";
            sync = false;
          };
        }
      ];
      # GOTCHA: Kea 3 only runs hook scripts from its scripts directory.
      systemd.services.kea-dhcp4-server.environment.KEA_HOOK_SCRIPTS_PATH = "${newDeviceScripts}";
    })
  ]);
}
