{ config, lib, pkgs, ... }:

with lib;

let
  legacyCfg = config.services.router.dnsZone;
  multiCfg = config.services.router.dnsZones;

  hostModule = types.submodule {
    options = {
      ipAddress = mkOption {
        type = types.str;
        example = "10.10.11.52";
        description = "IP address for this host";
      };

      ttl = mkOption {
        type = types.int;
        default = 3600;
        description = "TTL for DNS record in seconds";
      };

      aliases = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "alias1" "alias2" ];
        description = "CNAME aliases for this host";
      };
    };
  };

  zoneModule = types.submodule ({ name, ... }: {
    options = {
      nameserverIP = mkOption {
        type = types.str;
        default = "192.168.1.1";
        example = "10.10.10.1";
        description = "IP address of the nameserver (usually the router/gateway)";
      };

      staticHosts = mkOption {
        type = types.attrsOf hostModule;
        default = {};
        example = literalExpression ''
          {
            gateway = {
              ipAddress = "10.10.10.1";
              aliases = [ "router" "dns" ];
            };
            pve-gateway = {
              ipAddress = "10.10.11.52";
            };
          }
        '';
        description = "Static host records to add to this DNS zone";
      };

      aliases = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = {
          cache = "attic-cache";
        };
        description = "Additional CNAME aliases mapping alias name to target host";
      };

      allowDynamicUpdates = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to allow DHCP to dynamically register hosts";
      };

      reverseZone = {
        enable = mkEnableOption "automatic reverse DNS (PTR) records";

        networks = mkOption {
          type = types.listOf types.str;
          default = [];
          example = [ "10.10.10.0/24" "10.10.11.0/24" ];
          description = "Networks for which to create reverse zones";
        };
      };

      zoneConfig = mkOption {
        type = types.nullOr types.attrs;
        default = null;
        example = literalExpression ''
          {
            domain = "deepwatercreature.com";
            hosts = {
              gateway = { ipv4 = "10.10.10.1"; ipv6 = null; };
            };
          }
        '';
        description = "Reserved for external zone configuration imports";
      };
    };
  });

  legacyZone =
    optionalAttrs legacyCfg.enable {
      "${legacyCfg.zoneName}" = {
        inherit (legacyCfg)
          nameserverIP
          staticHosts
          allowDynamicUpdates
          zoneConfig
          reverseZone
          ;
        aliases = {};
      };
    };

  zoneNames = attrNames multiCfg;

  configuredZones =
    if zoneNames != [] then
      multiCfg
    else
      legacyZone;

  reverseZoneNameForNetwork =
    network:
    let
      parts = splitString "/" network;
      address = elemAt parts 0;
      prefixLength = toInt (elemAt parts 1);
      octets = splitString "." address;
      zoneOctetCount = prefixLength / 8;
    in
    assert (length parts == 2 && prefixLength > 0 && prefixLength <= 32 && mod prefixLength 8 == 0);
    "${concatStringsSep "." (reverseList (sublist 0 zoneOctetCount octets))}.in-addr.arpa";

  derivedReverseZones =
    foldl'
      (
        acc: zone:
        if zone.reverseZone.enable then
          foldl'
            (
              zoneAcc: network:
              zoneAcc
              // {
                "${reverseZoneNameForNetwork network}" = {
                  nameserverIP = zone.nameserverIP;
                  staticHosts = {};
                  aliases = {};
                  allowDynamicUpdates = zone.allowDynamicUpdates;
                  zoneConfig = null;
                  reverseZone = {
                    enable = false;
                    networks = [ ];
                  };
                };
              }
            )
            acc
            zone.reverseZone.networks
        else
          acc
      )
      { }
      (attrValues configuredZones);

  allZones = configuredZones // derivedReverseZones;

  hasZones = allZones != {};
  allZoneNames = attrNames allZones;

  zoneFileText =
    zoneName: zone:
    let
      recordText = concatStringsSep "\n" (
        mapAttrsToList (name: value: ''
          ${name}    IN      A       ${value.ipAddress}
          ${concatMapStringsSep "\n" (alias: "${alias}    IN      CNAME   ${name}") value.aliases}
        '') zone.staticHosts
      );

      aliasText = concatStringsSep "\n" (
        mapAttrsToList (alias: target: "${alias}    IN      CNAME   ${target}") zone.aliases
      );
    in
    ''
      $ORIGIN ${zoneName}.
      $TTL 3600
      @       IN      SOA     ns1.${zoneName}. admin.${zoneName}. (
                      ${toString (builtins.hashString "sha256" (builtins.toJSON {
                        inherit zoneName;
                        inherit (zone) staticHosts aliases;
                      }))}  ; serial
                      3600       ; refresh
                      900        ; retry
                      604800     ; expire
                      86400 )    ; minimum TTL

      @       IN      NS      ns1.${zoneName}.
      ns1     IN      A       ${zone.nameserverIP}

      ${recordText}
      ${aliasText}
    '';

  fqdn = zoneName: name: if name == "@" then zoneName else "${name}.${zoneName}";

  # Shell line that records a successfully synchronized record as managed.
  markManaged = zone: domain: type: value: ''
    printf '%s\n' ${escapeShellArg (builtins.toJSON { inherit zone domain type value; })} >> "$ADDED_FILE"
  '';

  zoneSyncScript =
    concatStringsSep "\n" (
      mapAttrsToList (
        zoneName: zone:
        let
          hostCommands = concatStringsSep "\n" (
            mapAttrsToList (name: value: ''
              echo "Adding DNS record: ${name}.${zoneName} -> ${value.ipAddress}"
              technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                -d "zone=${zoneName}" \
                -d "domain=${if name == "@" then zoneName else "${name}.${zoneName}"}" \
                -d "type=A" \
                -d "ttl=${toString value.ttl}" \
                -d "ipAddress=${value.ipAddress}" \
                -d "overwrite=true" \
                >/dev/null
              ${markManaged zoneName (fqdn zoneName name) "A" value.ipAddress}

              ${concatMapStringsSep "\n" (alias: ''
                echo "Adding alias: ${alias}.${zoneName} -> ${name}.${zoneName}"
                technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                  -d "zone=${zoneName}" \
                  -d "domain=${if alias == "@" then zoneName else "${alias}.${zoneName}"}" \
                  -d "type=CNAME" \
                  -d "ttl=${toString value.ttl}" \
                  -d "cname=${if name == "@" then zoneName else "${name}.${zoneName}"}" \
                  -d "overwrite=true" \
                  >/dev/null
                ${markManaged zoneName (fqdn zoneName alias) "CNAME" (fqdn zoneName name)}
              '') value.aliases}
            '') zone.staticHosts
          );

          aliasCommands = concatStringsSep "\n" (
            mapAttrsToList (alias: target: ''
              echo "Adding zone alias: ${alias}.${zoneName} -> ${target}.${zoneName}"
              technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                -d "zone=${zoneName}" \
                -d "domain=${if alias == "@" then zoneName else "${alias}.${zoneName}"}" \
                -d "type=CNAME" \
                -d "ttl=3600" \
                -d "cname=${if target == "@" then zoneName else "${target}.${zoneName}"}" \
                -d "overwrite=true" \
                >/dev/null
              ${markManaged zoneName (fqdn zoneName alias) "CNAME" (fqdn zoneName target)}
            '') zone.aliases
          );
        in
        ''
          echo "Ensuring DNS zone exists: ${zoneName}"
          if ! zone_exists "${zoneName}"; then
            technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/create?token=$TOKEN" \
              -d "zone=${zoneName}" \
              -d "type=Primary" \
              >/dev/null
          fi

          ${hostCommands}
          ${aliasCommands}
        ''
      ) allZones
    );

  # INVARIANT: every record the sync service owns. Persisted after each successful run so
  # the next run can delete records that were removed from the configuration.
  managedRecords = flatten (
    mapAttrsToList (
      zoneName: zone:
      (flatten (
        mapAttrsToList (
          name: value:
          [
            {
              zone = zoneName;
              domain = fqdn zoneName name;
              type = "A";
              value = value.ipAddress;
            }
          ]
          ++ map (alias: {
            zone = zoneName;
            domain = fqdn zoneName alias;
            type = "CNAME";
            value = fqdn zoneName name;
          }) value.aliases
        ) zone.staticHosts
      ))
      ++ mapAttrsToList (alias: target: {
        zone = zoneName;
        domain = fqdn zoneName alias;
        type = "CNAME";
        value = fqdn zoneName target;
      }) zone.aliases
    ) allZones
  );

  managedRecordsFile = pkgs.writeText "technitium-managed-records.json" (builtins.toJSON managedRecords);

  managedRecordsStateDir = "/var/lib/technitium-sync-static-hosts";

  sshHostEntries =
    concatStringsSep "\n\n" (
      flatten (
        mapAttrsToList (
          zoneName: zone:
          mapAttrsToList (
            name: _value:
            let
              shortPatterns = optionalString (length allZoneNames <= 1) " ${name}";
            in
            ''
              Host ${name}.${zoneName}${shortPatterns}
                  Hostname ${name}.${zoneName}
            ''
          ) zone.staticHosts
        ) allZones
      )
    );
in
{
  options.services.router = {
    dnsZone = {
      enable = mkEnableOption "DNS zone management with static host records";

      zoneName = mkOption {
        type = types.str;
        default = "lan.local";
        example = "deepwatercreature.com";
        description = "The DNS zone name for local network";
      };

      nameserverIP = mkOption {
        type = types.str;
        default = "192.168.1.1";
        example = "10.10.10.1";
        description = "IP address of the nameserver (usually the router/gateway)";
      };

      zoneConfig = mkOption {
        type = types.nullOr types.attrs;
        default = null;
        example = literalExpression ''
          {
            domain = "deepwatercreature.com";
            hosts = {
              gateway = { ipv4 = "10.10.10.1"; ipv6 = null; };
            };
          }
        '';
        description = "Reserved for external zone configuration imports";
      };

      staticHosts = mkOption {
        type = types.attrsOf hostModule;
        default = {};
        example = literalExpression ''
          {
            gateway = {
              ipAddress = "10.10.10.1";
              aliases = [ "router" "dns" ];
            };
          }
        '';
        description = "Static host records to add to DNS zone";
      };

      allowDynamicUpdates = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to allow DHCP to dynamically register hosts";
      };

      reverseZone = {
        enable = mkEnableOption "automatic reverse DNS (PTR) records";

        networks = mkOption {
          type = types.listOf types.str;
          default = [];
          example = [ "10.10.10.0/24" "10.10.11.0/24" ];
          description = "Networks for which to create reverse zones";
        };
      };
    };

    dnsZones = mkOption {
      type = types.attrsOf zoneModule;
      default = {};
      example = literalExpression ''
        {
          "deepwatercreature.com" = {
            nameserverIP = "10.10.10.1";
            staticHosts.gateway = {
              ipAddress = "10.10.10.1";
              aliases = [ "router" "dns" ];
            };
          };
          "lab.deepwatercreature.com" = {
            nameserverIP = "10.10.10.1";
            staticHosts.attic-cache.ipAddress = "10.10.11.39";
          };
        }
      '';
      description = "Multiple DNS zones keyed by zone name";
    };
  };

  config = mkIf hasZones {
    assertions = [
      {
        assertion = !(legacyCfg.enable && zoneNames != []);
        message = "Use either services.router.dnsZone or services.router.dnsZones, not both.";
      }
    ];

    environment.etc =
      (mapAttrs'
        (zoneName: zone:
          nameValuePair "technitium/zones/${zoneName}.zone" {
            text = zoneFileText zoneName zone;
            mode = "0644";
          })
        allZones)
      // {
        "technitium/static-hosts.json" = {
          text = builtins.toJSON allZones;
          mode = "0644";
        };
      };

    systemd.services.technitium-sync-static-hosts = {
      description = "Sync static DNS records to Technitium";
      after =
        [ "technitium-dns-server.service" ]
        ++ optional (config.systemd.services ? technitium-bootstrap-api-token) "technitium-bootstrap-api-token.service";
      wants =
        [ "technitium-dns-server.service" ]
        ++ optional (config.systemd.services ? technitium-bootstrap-api-token) "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "technitium-sync-static-hosts";
      };

      script = let
        technitiumSecretName =
          if config.services ? router-technitium then
            config.services.router-technitium.apiKeySecretName
          else
            null;
        apiToken =
          if config.systemd.services ? technitium-bootstrap-api-token then
            "/var/lib/private/technitium-dns-server/nix-router-api-token"
          else if technitiumSecretName != null && builtins.hasAttr technitiumSecretName (config.age.secrets or { }) then
            config.age.secrets.${technitiumSecretName}.path
          else
            "/dev/null";
      in
      ''
        set -euo pipefail

        for i in {1..30}; do
          if ${pkgs.curl}/bin/curl -s http://localhost:5380/api/dns/status >/dev/null 2>&1; then
            break
          fi
          echo "Waiting for Technitium DNS Server to start..."
          sleep 2
        done

        TOKEN=""
        if [ -f "${apiToken}" ]; then
          TOKEN=$(cat "${apiToken}")
        fi

        if [ -z "$TOKEN" ]; then
          echo "Technitium API token is empty or file not found at ${apiToken}; cannot sync DNS records" >&2
          exit 1
        fi

        technitium_request() {
          local response
          response="$("$@")"
          if [ -z "$response" ]; then
            echo "Technitium API returned an empty response" >&2
            return 1
          fi

          local status
          status="$(printf '%s' "$response" | ${pkgs.jq}/bin/jq -r '.status // empty' 2>/dev/null || true)"
          if [ "$status" = "error" ] || [ "$status" = "invalid-token" ]; then
            printf '%s\n' "$response" >&2
            return 1
          fi

          printf '%s' "$response"
        }

        zone_exists() {
          local zone_name="$1"
          local zones_json
          zones_json="$(technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/list?token=$TOKEN")"
          printf '%s' "$zones_json" | ${pkgs.jq}/bin/jq -e --arg zone "$zone_name" '
            (.response.zones // []) | any(.name == $zone)
          ' >/dev/null
        }

        STATE_FILE="${managedRecordsStateDir}/managed-records.json"
        PREV_FILE="$(mktemp)"
        RETAINED_FILE="$(mktemp)"
        ADDED_FILE="$(mktemp)"
        HAVE_PREV=0
        if [ -f "$STATE_FILE" ]; then
          cp "$STATE_FILE" "$PREV_FILE"
          HAVE_PREV=1
        else
          echo '[]' > "$PREV_FILE"
        fi

        write_state() {
          ${pkgs.jq}/bin/jq -s 'add | unique' "$@" > "$STATE_FILE.tmp"
          chmod 0644 "$STATE_FILE.tmp"
          mv "$STATE_FILE.tmp" "$STATE_FILE"
        }

        # INVARIANT: if the sync fails partway, keep ownership of the records that were
        # already written (plus everything owned before), but never claim
        # configured records that were not reached.
        on_exit() {
          rc=$?
          if [ "$rc" -ne 0 ]; then
            added_array="$(mktemp)"
            ${pkgs.jq}/bin/jq -s '.' "$ADDED_FILE" > "$added_array" \
              && write_state "$PREV_FILE" "$added_array" \
              || echo "Warning: could not record partially synced DNS records" >&2
            rm -f "$added_array"
          fi
          rm -f "$PREV_FILE" "$RETAINED_FILE" "$ADDED_FILE"
          exit "$rc"
        }
        trap on_exit EXIT

        ${zoneSyncScript}

        # INVARIANT: prune only state-file entries (zone, domain, type, value) that left
        # the config. Matching is by value, not record identity: a hand-made record
        # identical to a managed one is pruned too. Names compare case-insensitively.
        # WHY: docs/router-technitium-automation.md#static-host-records-and-pruning
        if [ "$HAVE_PREV" = 1 ]; then
          ${pkgs.jq}/bin/jq -c --slurpfile current ${managedRecordsFile} '
            def key: {zone: (.zone | ascii_downcase), domain: (.domain | ascii_downcase), type};
            ($current[0] | map(key)) as $keep
            | .[] | select(key as $k | ($keep | any(.[]; . == $k)) | not)
          ' "$PREV_FILE" | while IFS= read -r record; do
            zone="$(printf '%s' "$record" | ${pkgs.jq}/bin/jq -r .zone)"
            domain="$(printf '%s' "$record" | ${pkgs.jq}/bin/jq -r .domain)"
            type="$(printf '%s' "$record" | ${pkgs.jq}/bin/jq -r .type)"
            value="$(printf '%s' "$record" | ${pkgs.jq}/bin/jq -r .value)"
            # GOTCHA: look the record up first and only delete an exact match.
            # Technitium's delete endpoint ignores the target for CNAMEs, so
            # without this check an alias that was retargeted by hand would
            # be removed too. If the lookup fails, keep the entry and retry.
            if ! existing="$(technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/records/get?token=$TOKEN" \
                --data-urlencode "zone=$zone" \
                --data-urlencode "domain=$domain")"; then
              echo "Warning: could not look up $domain; will retry pruning on next run" >&2
              printf '%s\n' "$record" >> "$RETAINED_FILE"
              continue
            fi
            if ! printf '%s' "$existing" | ${pkgs.jq}/bin/jq -e --arg type "$type" --arg value "$value" '
                (.response.records // [])
                | any(.type == $type and (((.rData.ipAddress // .rData.cname // "") | ascii_downcase | rtrimstr(".")) == ($value | ascii_downcase | rtrimstr("."))))
              ' >/dev/null; then
              echo "Stale record $domain $type $value is already gone or was changed by hand; leaving it alone"
              continue
            fi

            echo "Removing stale DNS record: $domain $type $value"
            value_arg="ipAddress=$value"
            if [ "$type" = "CNAME" ]; then
              value_arg="cname=$value"
            fi
            if ! technitium_request ${pkgs.curl}/bin/curl -fsS "http://localhost:5380/api/zones/records/delete?token=$TOKEN" \
              --data-urlencode "zone=$zone" \
              --data-urlencode "domain=$domain" \
              --data-urlencode "type=$type" \
              --data-urlencode "$value_arg" \
              >/dev/null; then
              echo "Warning: could not remove $domain $type $value; will retry on next run" >&2
              printf '%s\n' "$record" >> "$RETAINED_FILE"
            fi
          done
        fi

        # New state: everything configured now, plus stale records that could
        # not be removed yet.
        jq_retained="$(mktemp)"
        ${pkgs.jq}/bin/jq -s '.' "$RETAINED_FILE" > "$jq_retained"
        write_state ${managedRecordsFile} "$jq_retained"
        rm -f "$jq_retained"

        echo "Static DNS records synchronized"
      '';
    };

    programs.ssh.extraConfig = mkIf (sshHostEntries != "") sshHostEntries;
  };
}
