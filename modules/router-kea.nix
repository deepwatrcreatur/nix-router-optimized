{
  config,
  options,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-kea;
  routedIfaces = config.services.router-networking.routedInterfaces or { };
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;

  # Auto-derive LAN interfaces from router-networking when none are specified.
  effectiveInterfaces =
    if cfg.dhcp4.interfaces != [ ] then
      cfg.dhcp4.interfaces
    else
      mapAttrsToList (_name: iface: iface.device) (
        filterAttrs (_name: iface: elem iface.role [ "lan" ]) routedIfaces
      );

  reservationModule = types.submodule {
    options = {
      hw-address = mkOption {
        type = types.str;
        description = "Client MAC address.";
      };
      ip-address = mkOption {
        type = types.str;
        description = "Reserved IPv4 address.";
      };
      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional hostname; triggers DDNS A-record registration when DDNS is enabled.";
      };
    };
  };

  poolRangeModule = types.submodule {
    options = {
      start = mkOption { type = types.str; description = "First address in the pool."; };
      end = mkOption { type = types.str; description = "Last address in the pool."; };
    };
  };

  # Script that writes the full Kea D2 config including TSIG secret at runtime.
  # Runs as ExecStartPre (+prefix = root) for kea-dhcp-ddns-server so the
  # secret never enters the Nix store and never appears in ps output.
  writeD2Config = pkgs.writeShellScript "kea-write-d2-config" ''
    set -euo pipefail
    TMPFILE=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$TMPFILE"' EXIT
    ${pkgs.coreutils}/bin/tr -d '\n' < ${escapeShellArg cfg.ddns.tsigKeyFile} > "$TMPFILE"
    RAW_REV=${escapeShellArg cfg.ddns.reverseZone}
    if [ "$RAW_REV" = "." ]; then
      REV_ZONE="."
    else
      REV_ZONE="$RAW_REV."
    fi
    ${pkgs.jq}/bin/jq -n \
      --arg keyName  ${escapeShellArg cfg.ddns.tsigKeyName} \
      --arg keyAlgo  ${escapeShellArg cfg.ddns.tsigAlgorithm} \
      --rawfile secret "$TMPFILE" \
      --arg fwdZone  "${cfg.ddns.forwardZone}." \
      --arg revZone  "$REV_ZONE" \
      --arg ip       ${escapeShellArg cfg.ddns.serverAddress} \
      --argjson port ${toString cfg.ddns.serverPort} \
      '{
        "DhcpDdns": {
          "ip-address": "127.0.0.1",
          "port": 53001,
          "tsig-keys": [
            {"name": $keyName, "algorithm": $keyAlgo, "secret": ($secret | rtrimstr("\n"))}
          ],
          "forward-ddns": {
            "ddns-domains": [
              {
                "name": $fwdZone,
                "key-name": $keyName,
                "dns-servers": [{"ip-address": $ip, "port": $port}]
              }
            ]
          },
          "reverse-ddns": {
            "ddns-domains": (if $revZone == "." then [] else [
              {
                "name": $revZone,
                "key-name": $keyName,
                "dns-servers": [{"ip-address": $ip, "port": $port}]
              }
            ] end)
          }
        }
      }' > /run/kea/dhcp-ddns-runtime.conf
    ${pkgs.coreutils}/bin/chmod 640 /run/kea/dhcp-ddns-runtime.conf
    ${pkgs.coreutils}/bin/chown root:kea /run/kea/dhcp-ddns-runtime.conf
  '';
in
{
  options.services.router-kea = {
    enable = mkEnableOption "Kea DHCPv4 + DDNS for router LAN clients";

    dhcp4 = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "LAN interfaces to serve DHCP on. Defaults to LAN-role interfaces from services.router-networking.";
      };

      subnet = mkOption {
        type = types.str;
        example = "10.10.0.0/16";
        description = "CIDR subnet for the DHCPv4 scope.";
      };

      gatewayAddress = mkOption {
        type = types.str;
        example = "10.10.10.1";
        description = "Default gateway advertised to clients (DHCP option 3).";
      };

      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DNS servers advertised to clients (DHCP option 6).";
      };

      poolRanges = mkOption {
        type = types.listOf poolRangeModule;
        default = [ ];
        example = [ { start = "10.10.10.100"; end = "10.10.10.250"; } ];
        description = "Dynamic address pool(s) within the subnet.";
      };

      defaultLeaseTimeSec = mkOption {
        type = types.int;
        default = 86400;
        description = "Default lease time in seconds.";
      };

      maxLeaseTimeSec = mkOption {
        type = types.int;
        default = 172800;
        description = "Maximum lease time in seconds.";
      };

      reservations = mkOption {
        type = types.listOf reservationModule;
        default = [ ];
        description = "Static DHCP reservations. Hostnames trigger DDNS A-record registration when DDNS is enabled.";
      };
    };

    ddns = {
      enable = mkEnableOption "Kea DHCP-DDNS (D2) for automatic DNS registration of leases";

      serverAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address of the DNS server to update via RFC2136.";
      };

      serverPort = mkOption {
        type = types.int;
        default = 53;
        description = "Port of the DNS server to update.";
      };

      tsigKeyFile = mkOption {
        type = types.str;
        example = "/run/agenix/kea-ddns-tsig-key";
        description = "Runtime path to the TSIG shared secret (base64, no trailing newline).";
      };

      tsigKeyName = mkOption {
        type = types.str;
        default = "kea-ddns";
        description = "TSIG key name as registered in the DNS server.";
      };

      tsigAlgorithm = mkOption {
        type = types.str;
        default = "HMAC-SHA256";
        description = "TSIG algorithm. Must match what the DNS server expects.";
      };

      forwardZone = mkOption {
        type = types.str;
        example = "deepwatercreature.com";
        description = "Forward zone name (without trailing dot).";
      };

      reverseZone = mkOption {
        type = types.str;
        default = ".";
        example = "10.10.in-addr.arpa";
        description = "Reverse zone name (without trailing dot). Set to \".\" to disable reverse updates.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
  {

    # ── DHCPv4 ────────────────────────────────────────────────────────────────

    services.kea.dhcp4 = {
      enable = true;
      settings = {
        valid-lifetime = cfg.dhcp4.defaultLeaseTimeSec;
        max-valid-lifetime = cfg.dhcp4.maxLeaseTimeSec;
        renew-timer = cfg.dhcp4.defaultLeaseTimeSec / 4;
        rebind-timer = (cfg.dhcp4.defaultLeaseTimeSec * 3) / 4;

        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };

        control-socket = {
          socket-type = "unix";
          socket-name = "/run/kea/dhcp4.sock";
        };

        interfaces-config = {
          dhcp-socket-type = "raw";
          interfaces = effectiveInterfaces;
        };

        subnet4 = [
          {
            id = 1;
            subnet = cfg.dhcp4.subnet;
            pools = map (r: { pool = "${r.start} - ${r.end}"; }) cfg.dhcp4.poolRanges;
            option-data =
              optional (cfg.dhcp4.gatewayAddress != "") {
                name = "routers";
                data = cfg.dhcp4.gatewayAddress;
              }
              ++ optional (cfg.dhcp4.dnsServers != [ ]) {
                name = "domain-name-servers";
                data = concatStringsSep ", " cfg.dhcp4.dnsServers;
              };
            reservations = map (
              r:
              { hw-address = r.hw-address; ip-address = r.ip-address; }
              // optionalAttrs (r.hostname != null) { hostname = r.hostname; }
            ) cfg.dhcp4.reservations;
          }
        ];
      } // optionalAttrs cfg.ddns.enable {
        dhcp-ddns = {
          enable-updates = true;
          server-ip = "127.0.0.1";
          server-port = 53001;
        };
        ddns-send-updates = true;
        ddns-qualifying-suffix = "${cfg.ddns.forwardZone}.";
        ddns-override-client-update = true;
      };
    };

    # ── DHCP-DDNS (D2) ────────────────────────────────────────────────────────
    # The TSIG key must not reach the Nix store. We supply a minimal placeholder
    # to satisfy the NixOS kea module assertion, then override ExecStart so the
    # real service reads from the runtime-generated config instead.

    services.kea.dhcp-ddns = mkIf cfg.ddns.enable {
      enable = true;
      # Placeholder satisfies `xor (settings == null) (configFile == null)`.
      # The actual config is written to /run/kea/dhcp-ddns-runtime.conf by
      # the preStart script below.
      configFile = pkgs.writeText "kea-dhcp-ddns-placeholder.json" ''{"DhcpDdns": {}}'';
    };

    systemd.services.kea-dhcp-ddns-server = mkIf cfg.ddns.enable {
      # Generate the real config (with TSIG secret) before the daemon starts.
      serviceConfig.ExecStartPre = [ "+${writeD2Config}" ];
      # Override the ExecStart from the kea module to use our runtime config.
      serviceConfig.ExecStart = mkForce (
        lib.escapeShellArgs [
          "${pkgs.kea}/bin/kea-dhcp-ddns"
          "-c"
          "/run/kea/dhcp-ddns-runtime.conf"
        ]
      );
    };

  }

  # ── Firewall ────────────────────────────────────────────────────────────────
  # Guard behind hasRouterFirewall so the option is not referenced when
  # router-firewall is not loaded as a module.
  (if hasRouterFirewall then {
    services.router-firewall.trustedUdpPorts = mkIf (
      config.services.router-firewall.enable or false
    ) [ 67 68 ];
  } else {})
]);
}
