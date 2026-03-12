{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router.dnsZone;
  
  # Convert host records to Technitium zone format
  generateZoneRecords = hosts: concatStringsSep "\n" (
    mapAttrsToList (name: value: ''
      {
        "name": "${name}",
        "type": "A",
        "ttl": ${toString value.ttl},
        "ipAddress": "${value.ipAddress}"
      }
    '') hosts
  );

  zoneConfigFile = pkgs.writeText "dns-zone-records.json" (builtins.toJSON {
    zoneName = cfg.zoneName;
    records = mapAttrsToList (name: value: {
      inherit name;
      type = "A";
      ttl = value.ttl;
      ipAddress = value.ipAddress;
    }) cfg.staticHosts;
  });

in {
  options.services.router.dnsZone = {
    enable = mkEnableOption "DNS zone management with static host records";

    zoneName = mkOption {
      type = types.str;
      default = "lan.local";
      example = "deepwatercreature.com";
      description = "The DNS zone name for local network";
    };

    staticHosts = mkOption {
      type = types.attrsOf (types.submodule {
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
      });
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

  config = mkIf cfg.enable {
    # Generate zone file for Technitium
    environment.etc."technitium/zones/${cfg.zoneName}.zone" = mkIf (cfg.staticHosts != {}) {
      text = ''
        $ORIGIN ${cfg.zoneName}.
        $TTL 3600
        @       IN      SOA     ns1.${cfg.zoneName}. admin.${cfg.zoneName}. (
                        ${toString (builtins.hashString "sha256" (builtins.toJSON cfg.staticHosts))}  ; serial
                        3600       ; refresh
                        900        ; retry
                        604800     ; expire
                        86400 )    ; minimum TTL
        
        @       IN      NS      ns1.${cfg.zoneName}.
        ns1     IN      A       ${config.services.router.interfaces.lan.ipAddress}
        
        ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
          ${name}    IN      A       ${value.ipAddress}
          ${concatMapStringsSep "\n" (alias: "${alias}    IN      CNAME   ${name}") value.aliases}
        '') cfg.staticHosts)}
      '';
      mode = "0644";
    };

    # Store JSON format for API-based management
    environment.etc."technitium/static-hosts.json" = {
      text = builtins.toJSON cfg.staticHosts;
      mode = "0644";
    };

    # Script to sync static hosts to Technitium via API
    systemd.services.technitium-sync-static-hosts = mkIf (cfg.staticHosts != {}) {
      description = "Sync static DNS records to Technitium";
      after = [ "technitium-dns-server.service" ];
      wants = [ "technitium-dns-server.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = let
        apiToken = if (config.age.secrets ? technitium-api-key) 
                   then config.age.secrets.technitium-api-key.path
                   else "/dev/null";
      in ''
        set -euo pipefail
        
        # Wait for Technitium to be ready
        for i in {1..30}; do
          if ${pkgs.curl}/bin/curl -s http://localhost:5380/api/dns/status >/dev/null 2>&1; then
            break
          fi
          echo "Waiting for Technitium DNS Server to start..."
          sleep 2
        done

        # Read API token if available
        TOKEN=""
        if [ -f "${apiToken}" ]; then
          TOKEN=$(cat "${apiToken}")
        fi

        # Ensure zone exists
        ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/create" \
          -H "Authorization: Bearer $TOKEN" \
          -d "zone=${cfg.zoneName}" \
          -d "type=Primary" || true

        # Add each static host record
        ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
          echo "Adding DNS record: ${name}.${cfg.zoneName} -> ${value.ipAddress}"
          ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/records/add" \
            -H "Authorization: Bearer $TOKEN" \
            -d "zone=${cfg.zoneName}" \
            -d "domain=${name}" \
            -d "type=A" \
            -d "ttl=${toString value.ttl}" \
            -d "ipAddress=${value.ipAddress}" \
            -d "overwrite=true" || echo "Failed to add ${name}"
          
          ${concatMapStringsSep "\n" (alias: ''
            echo "Adding alias: ${alias}.${cfg.zoneName} -> ${name}.${cfg.zoneName}"
            ${pkgs.curl}/bin/curl -s "http://localhost:5380/api/zones/records/add" \
              -H "Authorization: Bearer $TOKEN" \
              -d "zone=${cfg.zoneName}" \
              -d "domain=${alias}" \
              -d "type=CNAME" \
              -d "ttl=${toString value.ttl}" \
              -d "cname=${name}.${cfg.zoneName}" \
              -d "overwrite=true" || echo "Failed to add alias ${alias}"
          '') value.aliases}
        '') cfg.staticHosts)}

        echo "Static DNS records synchronized"
      '';
    };

    # Generate SSH config from DNS zone
    programs.ssh.extraConfig = mkIf (cfg.staticHosts != {}) (
      concatStringsSep "\n\n" (mapAttrsToList (name: value: ''
        Host ${name}
            Hostname ${name}.${cfg.zoneName}
      '') cfg.staticHosts)
    );
  };
}
