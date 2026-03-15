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

  allZones =
    if zoneNames != [] then
      multiCfg
    else
      legacyZone;

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

  zoneSyncScript =
    concatStringsSep "\n" (
      mapAttrsToList (
        zoneName: zone:
        let
          hostCommands = concatStringsSep "\n" (
            mapAttrsToList (name: value: ''
              echo "Adding DNS record: ${name}.${zoneName} -> ${value.ipAddress}"
              ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                -d "zone=${zoneName}" \
                -d "domain=${name}" \
                -d "type=A" \
                -d "ttl=${toString value.ttl}" \
                -d "ipAddress=${value.ipAddress}" \
                -d "overwrite=true" || echo "Failed to add ${name}.${zoneName}"

              ${concatMapStringsSep "\n" (alias: ''
                echo "Adding alias: ${alias}.${zoneName} -> ${name}.${zoneName}"
                ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                  -d "zone=${zoneName}" \
                  -d "domain=${alias}" \
                  -d "type=CNAME" \
                  -d "ttl=${toString value.ttl}" \
                  -d "cname=${name}.${zoneName}" \
                  -d "overwrite=true" || echo "Failed to add alias ${alias}.${zoneName}"
              '') value.aliases}
            '') zone.staticHosts
          );

          aliasCommands = concatStringsSep "\n" (
            mapAttrsToList (alias: target: ''
              echo "Adding zone alias: ${alias}.${zoneName} -> ${target}.${zoneName}"
              ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/records/add?token=$TOKEN" \
                -d "zone=${zoneName}" \
                -d "domain=${alias}" \
                -d "type=CNAME" \
                -d "ttl=3600" \
                -d "cname=${target}.${zoneName}" \
                -d "overwrite=true" || echo "Failed to add zone alias ${alias}.${zoneName}"
            '') zone.aliases
          );
        in
        ''
          echo "Ensuring DNS zone exists: ${zoneName}"
          ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/create?token=$TOKEN" \
            -d "zone=${zoneName}" \
            -d "type=Primary" || true

          ${hostCommands}
          ${aliasCommands}
        ''
      ) allZones
    );

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
      after = [ "technitium-dns-server.service" ];
      wants = [ "technitium-dns-server.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = let
        apiToken =
          if config.age.secrets ? technitium-api-key then
            config.age.secrets.technitium-api-key.path
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

        ${zoneSyncScript}

        echo "Static DNS records synchronized"
      '';
    };

    programs.ssh.extraConfig = mkIf (sshHostEntries != "") sshHostEntries;
  };
}
