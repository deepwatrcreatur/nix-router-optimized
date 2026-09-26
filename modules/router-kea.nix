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
  hasRouterDnsService = hasAttrByPath [ "services" "router-dns-service" "searchDomains" ] options;
  hasRouterNtp = hasAttrByPath [ "services" "router-ntp" "enable" ] options;
  hasRouterNat64 = hasAttrByPath [ "services" "router-nat64" "enable" ] options;
  hasRouterDns64 = hasAttrByPath [ "services" "router-dns64" "enable" ] options;
  nat64Enabled = hasRouterNat64 && (config.services.router-nat64.enable or false);
  dns64Enabled = hasRouterDns64 && (config.services.router-dns64.enable or false);

  routerKeaExporter = pkgs.writers.writePython3Bin "router-kea-exporter" { } (
    builtins.readFile ./router-kea/router-kea-exporter.py
  );

  # Auto-derive LAN interfaces from router-networking when none are specified.
  effectiveInterfaces =
    if cfg.dhcp4.interfaces != [ ] then
      cfg.dhcp4.interfaces
    else
      mapAttrsToList (_name: iface: iface.device) (
        filterAttrs (_name: iface: elem iface.role [ "lan" ]) routedIfaces
      );

  # TECHNICAL GUARDRAIL: Kea 3.x on Linux fails to poll the raw socket for
  # receiving if the interface is bound with an address qualifier (e.g. eth0/10.0.0.1).
  # We must ensure that in raw mode, only bare interface names are used.
  hasAddressQualifiedInterface = any (i: strings.hasInfix "/" i) effectiveInterfaces;

  servedRoutedInterfaces = filterAttrs (_name: iface: elem iface.device effectiveInterfaces) routedIfaces;

  derivedSearchDomains =
    unique (flatten (mapAttrsToList (_name: iface: iface.domains or [ ]) servedRoutedInterfaces));

  effectiveSearchDomains =
    if cfg.dhcp4.searchDomains != [ ] then
      cfg.dhcp4.searchDomains
    else if hasRouterDnsService then
      config.services.router-dns-service.searchDomains
    else
      derivedSearchDomains;

  parseInt = s: builtins.fromJSON s;

  parseIPv4 =
    ip:
    let
      octets = splitString "." ip;
      parsedOctets = map parseInt octets;
      validOctets = all (o: o >= 0 && o <= 255) parsedOctets;
    in
    assert length octets == 4;
    assert validOctets;
    ((elemAt parsedOctets 0) * 16777216)
    + ((elemAt parsedOctets 1) * 65536)
    + ((elemAt parsedOctets 2) * 256)
    + (elemAt parsedOctets 3);

  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);

  parseSubnet =
    cidr:
    let
      parts = splitString "/" cidr;
      prefixLength = parseInt (elemAt parts 1);
      hostCount = pow2 (32 - prefixLength);
      network = builtins.div (parseIPv4 (elemAt parts 0)) hostCount * hostCount;
    in
    assert length parts == 2;
    assert prefixLength >= 0 && prefixLength <= 32;
    {
      inherit prefixLength hostCount network;
      broadcast = network + hostCount - 1;
    };

  subnetInfo = parseSubnet cfg.dhcp4.subnet;
  inSubnet = ipInt: ipInt >= subnetInfo.network && ipInt <= subnetInfo.broadcast;
  isUsableHostAddress = ipInt: ipInt > subnetInfo.network && ipInt < subnetInfo.broadcast;
  routerNtpLanSubnets =
    if hasRouterNtp then
      config.services.router-ntp.lanSubnets or [ ]
    else
      [ ];
  routerNtpAllowsDhcpSubnet =
    any (
      lanSubnet:
      let
        lanInfo = parseSubnet lanSubnet;
      in
      subnetInfo.network >= lanInfo.network && subnetInfo.broadcast <= lanInfo.broadcast
    ) routerNtpLanSubnets;
  effectiveNtpServers =
    if cfg.dhcp4.ntpServers != [ ] then
      cfg.dhcp4.ntpServers
    else if hasRouterNtp && (config.services.router-ntp.enable or false) && routerNtpAllowsDhcpSubnet && cfg.dhcp4.gatewayAddress != "" then
      [ cfg.dhcp4.gatewayAddress ]
    else
      [ ];

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

  keaDhcp4LeaseHeader =
    "address,hwaddr,client_id,valid_lifetime,expire,subnet_id,fqdn_fwd,fqdn_rev,hostname,state,user_context,pool_id";

  ensureKeaLeaseStateScript = pkgs.writeShellScript "router-kea-ensure-state" ''
    set -euo pipefail

    install -d -m 0750 -o kea -g kea /var/lib/private/kea /var/lib/kea

    expected_header='${keaDhcp4LeaseHeader}'

    for lease_file in /var/lib/private/kea/dhcp4.leases /var/lib/private/kea/dhcp4.leases.2 /var/lib/kea/dhcp4.leases /var/lib/kea/dhcp4.leases.2; do
      if [ ! -e "$lease_file" ]; then
        continue
      fi

      if [ -s "$lease_file" ]; then
        header="$(head -n 1 "$lease_file" || true)"
        if [ "$header" != "$expected_header" ]; then
          backup="$lease_file.incompatible.$(date +%s)"
          cp -a "$lease_file" "$backup"
          : > "$lease_file"
          echo "router-kea-ensure-state: reset incompatible lease file header in $lease_file (backup: $backup)" >&2
        fi

        if ${pkgs.gawk}/bin/gawk -F, '$10 == "1" { exit 0 } END { exit 1 }' "$lease_file" 2>/dev/null; then
          temp_clean="$lease_file.clean.$(date +%s)"
          ${pkgs.gawk}/bin/gawk -F, 'NR==1 || $10 != "1"' "$lease_file" > "$temp_clean" || true
          cat "$temp_clean" > "$lease_file"
          rm -f "$temp_clean"
          echo "router-kea-ensure-state: purged declined leases from $lease_file" >&2
        fi
      fi

      chown kea:kea "$lease_file" 2>/dev/null || true
      chmod 0640 "$lease_file" 2>/dev/null || true
    done

    ${pkgs.findutils}/bin/find /var/lib/private/kea /var/lib/kea -name "dhcp4.leases.incompatible.*" -mtime +1 -delete 2>/dev/null || true
  '';

  waitForLanReadyScript = pkgs.writeShellScript "router-kea-wait-for-lan-ready" ''
    set -euo pipefail
    SECONDS=0
    ${concatMapStringsSep "\n" (iface: ''
      while [ "$SECONDS" -lt 30 ]; do
        if ${pkgs.iproute2}/bin/ip -o link show dev ${escapeShellArg iface} 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "LOWER_UP"; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
    '') effectiveInterfaces}
  '';
in
{
  options.services.router-kea = {
    enable = mkEnableOption "Kea DHCPv4 + DDNS for router LAN clients";

    dhcp4 = {
      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          LAN interfaces to serve DHCP on. Defaults to LAN-role interfaces from
          services.router-networking.

          WARNING: In raw socket mode (default), do NOT use address qualifiers
          (e.g. "eth0/10.0.0.1"). Kea 3.x fails to poll for broadcasts on
          address-qualified raw sockets.
        '';
      };

      outboundInterface = mkOption {
        type = types.enum [
          "same-as-inbound"
          "use-routing"
        ];
        default = if cfg.dhcp4.ha.enable then "use-routing" else "same-as-inbound";
        defaultText = literalExpression ''if config.services.router-kea.dhcp4.ha.enable then "use-routing" else "same-as-inbound"'';
        description = ''
          Kea outbound-interface mode for DHCPv4 replies. `use-routing` is
          strongly recommended for HA/VRRP deployments to ensure broadcast
          replies reach clients through the correct kernel path.
        '';
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

      ntpServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "10.10.10.1" ];
        description = ''
          NTP servers advertised to clients (DHCP option 42). Defaults to the
          configured gateway/router address when `services.router-ntp.enable`
          is true.
        '';
      };

      searchDomains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "deepwatercreature.com" ];
        description = ''
          Search domains advertised to clients (DHCP options 15 and 119).
          Defaults to `services.router-dns-service.searchDomains` when that
          module is loaded, otherwise to the served routed interface domains.
        '';
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

      matchClientId = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether Kea matches clients by DHCP client-identifier option (DUID) before falling back to MAC address.
          Default false matches strictly by physical MAC address, preventing DUID churn from exhausting the IP pool.
        '';
      };

      declineProbationPeriodSec = mkOption {
        type = types.int;
        default = 300;
        description = ''
          Time in seconds a declined lease remains in the declined state before returning to the available pool.
          Kea default is 86400 (24 hours). 300 seconds allows swift recovery from transient IP collision conflicts.
        '';
      };

      expiredLeasesProcessing = {
        reclaimTimerWaitTime = mkOption {
          type = types.int;
          default = 10;
          description = "Time in seconds between lease reclamation cycles.";
        };
        flushReclaimedTimerWaitTime = mkOption {
          type = types.int;
          default = 25;
          description = "Time in seconds between flushing reclaimed leases to database.";
        };
        holdReclaimedTime = mkOption {
          type = types.int;
          default = 300;
          description = "Time in seconds reclaimed leases are held before re-entering free pool.";
        };
        maxReclaimLeases = mkOption {
          type = types.int;
          default = 100;
          description = "Maximum number of leases processed in a single reclaim cycle.";
        };
        maxReclaimTime = mkOption {
          type = types.int;
          default = 250;
          description = "Maximum time in milliseconds a reclaim cycle is allowed to take.";
        };
      };

      waitForCarrier = mkOption {
        type = types.bool;
        default = true;
        description = "Wait up to 30 seconds for served LAN interface(s) to achieve carrier before starting Kea.";
      };

      ensureLeaseState = mkOption {
        type = types.bool;
        default = true;
        description = "Validate Kea lease CSV header format and purge declined leases on service startup.";
      };

      reservations = mkOption {
        type = types.listOf reservationModule;
        default = [ ];
        description = "Static DHCP reservations. Hostnames trigger DDNS A-record registration when DDNS is enabled.";
      };

      pxe = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to advertise PXE boot options on this segment.";
            };

            bootServerAddress = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional PXE boot server address (next-server).";
            };

            bootServerName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional PXE boot server name (tftp-server-name).";
            };

            bootFilename = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "PXE boot filename or URL (boot-file-name).";
            };
          };
        };
        default = { };
        description = "Typed PXE boot advertisement options for this routed segment.";
      };

      ipv6OnlyPreferred = {
        enable = mkEnableOption ''
          RFC 8925 DHCP option 108 (IPv6-Only Preferred).

          When enabled, Kea advertises option 108 to tell IPv6-capable clients
          they may forgo their IPv4 address for the configured wait period.
          This is intended for IPv6-mostly LANs with a working NAT64/DNS64 path.
        '';

        v6OnlyWaitSec = mkOption {
          type = types.ints.between 0 65535;
          default = 300;
          description = ''
            V6ONLY_WAIT timer in seconds (RFC 8925 section 3).
            The client will prefer IPv6 for this duration before re-requesting
            IPv4. RFC 8925 recommends 300-1800 seconds.
          '';
        };
      };

      ha = {
        enable = mkEnableOption "Kea DHCPv4 High Availability (Load Balancing/Failover)";
        thisServerName = mkOption {
          type = types.str;
          example = "router-primary";
          description = "Name of this Kea server in the HA group.";
        };
        role = mkOption {
          type = types.enum [ "primary" "secondary" ];
          description = "Role of this server in the HA group.";
        };
        peerAddress = mkOption {
          type = types.str;
          description = "IP address of the peer Kea server.";
        };
        localAddress = mkOption {
          type = types.str;
          default = "0.0.0.0";
          example = "192.168.100.100";
          description = ''
            IP address this node advertises for its own Kea HA endpoint. In a
            multi-node deployment this must be reachable by the peer.

            WARNING: Using 127.0.0.1 (previous default) will break HA sync between nodes.
          '';
        };
        peerName = mkOption {
          type = types.str;
          example = "router-backup";
          description = "Name of the peer Kea server.";
        };
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

    exporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Kea metrics exporter service for Prometheus and router-dashboard monitoring.";
      };

      port = mkOption {
        type = types.port;
        default = 9547;
        description = "HTTP port for router-kea-exporter Prometheus metrics endpoint.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Auto-derive LAN interfaces from router-networking when none are specified.
      assertions = [
        {
          assertion = !hasAddressQualifiedInterface;
          message = ''
            Kea regression check failed: The interface list contains an address qualifier (e.g. eth0/10.0.0.1).
            Kea 3.x on Linux fails to poll for broadcasts when raw sockets are address-qualified.
            Use a bare interface name (e.g. "eth0") instead.
          '';
        }
        {
          assertion = cfg.dhcp4.ipv6OnlyPreferred.enable -> nat64Enabled;
          message = ''
            router-kea: ipv6OnlyPreferred (DHCP option 108) requires a working NAT64
            path. Enable services.router-nat64 or disable ipv6OnlyPreferred.
            Without NAT64, IPv6-only clients will lose access to IPv4-only destinations.
          '';
        }
        {
          assertion = cfg.dhcp4.ipv6OnlyPreferred.enable -> dns64Enabled;
          message = ''
            router-kea: ipv6OnlyPreferred (DHCP option 108) requires DNS64 synthesis.
            Enable services.router-dns64 or disable ipv6OnlyPreferred.
            Without DNS64, IPv6-only clients cannot discover NAT64-translated addresses.
          '';
        }
      ]
      ++ concatMap (
        r:
        let
          startInt = parseIPv4 r.start;
          endInt = parseIPv4 r.end;
          poolLabel = "${r.start} - ${r.end}";
        in
        [
          {
            assertion = inSubnet startInt && inSubnet endInt;
            message = "router-kea pool ${poolLabel} must stay within subnet ${cfg.dhcp4.subnet}.";
          }
          {
            assertion = startInt <= endInt;
            message = "router-kea pool ${poolLabel} must not have start after end.";
          }
          {
            assertion = isUsableHostAddress startInt;
            message = "router-kea pool ${poolLabel} must start on a usable host address, not the subnet network or broadcast address.";
          }
          {
            assertion = isUsableHostAddress endInt;
            message = "router-kea pool ${poolLabel} must end on a usable host address, not the subnet network or broadcast address.";
          }
        ]
      ) cfg.dhcp4.poolRanges
      ++ (flatten (map (ifaceName:
        let
          matchingRouted = filterAttrs (_n: i: i.device == ifaceName) routedIfaces;
        in
          if matchingRouted != { } then
            let
              rIface = head (attrValues matchingRouted);
              ipLib = import ./lib/ip.nix { inherit lib; };
            in [
              {
                assertion = ipLib.cidrContains rIface.ipv4Address cfg.dhcp4.subnet;
                message = "router-kea: dhcp4.subnet (${cfg.dhcp4.subnet}) is not contained within the subnet of bound interface ${rIface.device} (${rIface.ipv4Address}).";
              }
            ]
          else [ ]
      ) effectiveInterfaces));

      # ── DHCPv4 ────────────────────────────────────────────────────────────────

      services.kea.dhcp4 = {
        enable = true;
        settings = {
          # RFC 8925 option 108 is not a Kea built-in; define it as a custom option.
          option-def = mkIf cfg.dhcp4.ipv6OnlyPreferred.enable [
            {
              name = "v6-only-preferred";
              code = 108;
              type = "uint32";
              space = "dhcp4";
            }
          ];

          valid-lifetime = cfg.dhcp4.defaultLeaseTimeSec;
          max-valid-lifetime = cfg.dhcp4.maxLeaseTimeSec;
          renew-timer = cfg.dhcp4.defaultLeaseTimeSec / 4;
          rebind-timer = (cfg.dhcp4.defaultLeaseTimeSec * 3) / 4;
          decline-probation-period = cfg.dhcp4.declineProbationPeriodSec;
          match-client-id = cfg.dhcp4.matchClientId;
          host-reservation-identifiers = [ "hw-address" ];
          expired-leases-processing = {
            reclaim-timer-wait-time = cfg.dhcp4.expiredLeasesProcessing.reclaimTimerWaitTime;
            flush-reclaimed-timer-wait-time = cfg.dhcp4.expiredLeasesProcessing.flushReclaimedTimerWaitTime;
            hold-reclaimed-time = cfg.dhcp4.expiredLeasesProcessing.holdReclaimedTime;
            max-reclaim-leases = cfg.dhcp4.expiredLeasesProcessing.maxReclaimLeases;
            max-reclaim-time = cfg.dhcp4.expiredLeasesProcessing.maxReclaimTime;
          };

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
            outbound-interface = cfg.dhcp4.outboundInterface;
          };

          hooks-libraries = mkIf cfg.dhcp4.ha.enable [
            {
              library = "${pkgs.kea}/lib/kea/hooks/libdhcp_lease_cmds.so";
            }
            {
              library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
              parameters = {
                high-availability = [
                  {
                    this-server-name = cfg.dhcp4.ha.thisServerName;
                    mode = "load-balancing";
                    heartbeat-delay = 10000;
                    max-response-delay = 60000;
                    max-unacked-clients = 0;
                    peers = [
                      {
                        name = cfg.dhcp4.ha.thisServerName;
                        url = "http://${cfg.dhcp4.ha.localAddress}:8000/";
                        role = cfg.dhcp4.ha.role;
                      }
                      {
                        name = cfg.dhcp4.ha.peerName;
                        url = "http://${cfg.dhcp4.ha.peerAddress}:8000/";
                        role = if cfg.dhcp4.ha.role == "primary" then "secondary" else "primary";
                      }
                    ];
                  }
                ];
              };
            }
          ];

          subnet4 = [
            {
              id = 1;
              subnet = cfg.dhcp4.subnet;
              pools = map (r: { pool = "${r.start} - ${r.end}"; }) cfg.dhcp4.poolRanges;
              next-server = mkIf (cfg.dhcp4.pxe.enable && cfg.dhcp4.pxe.bootServerAddress != null) cfg.dhcp4.pxe.bootServerAddress;
              option-data =
                let
                  pxeCfg = cfg.dhcp4.pxe;
                in
                optional (cfg.dhcp4.gatewayAddress != "") {
                  name = "routers";
                  data = cfg.dhcp4.gatewayAddress;
                }
                ++ optional (cfg.dhcp4.dnsServers != [ ]) {
                  name = "domain-name-servers";
                  data = concatStringsSep ", " cfg.dhcp4.dnsServers;
                }
                ++ optional (effectiveSearchDomains != [ ]) {
                  name = "domain-name";
                  data = head effectiveSearchDomains;
                }
                ++ optional (effectiveSearchDomains != [ ]) {
                  name = "domain-search";
                  data = concatStringsSep ", " effectiveSearchDomains;
                }
                ++ optional (effectiveNtpServers != [ ]) {
                  name = "ntp-servers";
                  data = concatStringsSep ", " effectiveNtpServers;
                }
                ++ optional (pxeCfg.enable && pxeCfg.bootServerName != null) {
                  name = "tftp-server-name";
                  data = pxeCfg.bootServerName;
                }
                ++ optional (pxeCfg.enable && pxeCfg.bootFilename != null) {
                  name = "boot-file-name";
                  data = pxeCfg.bootFilename;
                }
                ++ optional cfg.dhcp4.ipv6OnlyPreferred.enable {
                  code = 108;
                  name = "v6-only-preferred";
                  space = "dhcp4";
                  csv-format = true;
                  data = toString cfg.dhcp4.ipv6OnlyPreferred.v6OnlyWaitSec;
                };
              reservations = map (
                r:
                {
                  hw-address = r.hw-address;
                  ip-address = r.ip-address;
                }
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

      systemd.services.kea-dhcp4-server = {
        serviceConfig.ExecStartPre = mkBefore (
          optional cfg.dhcp4.ensureLeaseState "+${ensureKeaLeaseStateScript}"
          ++ optional cfg.dhcp4.waitForCarrier "+${waitForLanReadyScript}"
        );
      };

      systemd.services.router-kea-exporter = mkIf cfg.exporter.enable {
        description = "Kea DHCP Metrics Exporter & Health Monitor";
        after = [ "kea-dhcp4-server.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${routerKeaExporter}/bin/router-kea-exporter --port ${toString cfg.exporter.port}";
          Restart = "always";
          RestartSec = "5s";
          User = "root";
          RuntimeDirectory = "router";
        };
      };
    }

    # ── Firewall ────────────────────────────────────────────────────────────────
    # Guard behind hasRouterFirewall so the option is not referenced when
    # router-firewall is not loaded as a module.
    (if hasRouterFirewall then {
      services.router-firewall.trustedUdpPorts = mkIf (
        config.services.router-firewall.enable or false
      ) [ 67 68 ];
      services.router-firewall.trustedTcpPorts = mkIf (
        config.services.router-firewall.enable or false && cfg.dhcp4.ha.enable
      ) [ 8000 ];
    } else { })
  ]);
}
