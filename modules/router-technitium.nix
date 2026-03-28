{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-technitium;
  secretName = cfg.apiKeySecretName;
  hasApiSecret = secretName != null && hasAttr secretName config.age.secrets;
  reservationModule = types.submodule {
    options = {
      scope = mkOption {
        type = types.str;
        default = "LAN";
        description = "Technitium DHCP scope name that should own this reservation.";
      };

      macAddress = mkOption {
        type = types.str;
        example = "BC:24:11:A4:01:6F";
        description = "MAC address used for the DHCP reservation.";
      };

      ipAddress = mkOption {
        type = types.str;
        example = "10.10.11.70";
        description = "Reserved IPv4 address.";
      };

      hostName = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "authentik-host";
        description = "Optional hostname written into the reservation.";
      };

      comments = mkOption {
        type = types.str;
        default = "";
        description = "Optional free-form comment stored with the reservation.";
      };
    };
  };
  dhcpReservationsJson = pkgs.writeText "technitium-dhcp-reservations.json" (
    builtins.toJSON (mapAttrsToList (name: reservation: reservation // { inherit name; }) cfg.dhcpReservations)
  );
  dhcpReservationScript = pkgs.writeShellScript "technitium-sync-dhcp-reservations" ''
    set -euo pipefail

    if [ -z "${if hasApiSecret then config.age.secrets.${secretName}.path else ""}" ] || [ ! -f "${if hasApiSecret then config.age.secrets.${secretName}.path else "/nonexistent"}" ]; then
      echo "Technitium API token file not found; cannot sync DHCP reservations" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(${pkgs.coreutils}/bin/cat "${if hasApiSecret then config.age.secrets.${secretName}.path else "/nonexistent"}")"

    ${pkgs.jq}/bin/jq -c '.[]' ${dhcpReservationsJson} | while read -r reservation; do
      scope="$(${pkgs.jq}/bin/jq -r '.scope' <<<"$reservation")"
      mac="$(${pkgs.jq}/bin/jq -r '.macAddress' <<<"$reservation")"
      ip="$(${pkgs.jq}/bin/jq -r '.ipAddress' <<<"$reservation")"
      hostname="$(${pkgs.jq}/bin/jq -r '.hostName // ""' <<<"$reservation")"
      comments="$(${pkgs.jq}/bin/jq -r '.comments // ""' <<<"$reservation")"
      name="$(${pkgs.jq}/bin/jq -r '.name' <<<"$reservation")"

      existing="$(${pkgs.curl}/bin/curl -fsS \
        "http://127.0.0.1:5380/api/dhcp/scopes/get?token=$TOKEN&name=$scope" \
        | ${pkgs.jq}/bin/jq -c --arg mac "$mac" '.response.reservedLeases // [] | map(select(.hardwareAddress == $mac)) | first')"

      if [ "$existing" != "null" ]; then
        existing_ip="$(${pkgs.jq}/bin/jq -r '.address // ""' <<<"$existing")"
        existing_host="$(${pkgs.jq}/bin/jq -r '.hostName // ""' <<<"$existing")"
        if [ "$existing_ip" = "$ip" ] && [ "$existing_host" = "$hostname" ]; then
          echo "DHCP reservation $name already present ($mac -> $ip)"
          continue
        fi

        echo "DHCP reservation $name already exists with different values ($mac -> $existing_ip); leaving it unchanged" >&2
        continue
      fi

      echo "Adding DHCP reservation $name: $mac -> $ip in scope $scope"
      ${pkgs.curl}/bin/curl -fsS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "name=$scope" \
        --data-urlencode "hardwareAddress=$mac" \
        --data-urlencode "ipAddress=$ip" \
        --data-urlencode "hostName=$hostname" \
        --data-urlencode "comments=$comments" \
        "http://127.0.0.1:5380/api/dhcp/scopes/addReservedLease" \
        >/dev/null
    done

    echo "Technitium DHCP reservations synchronized"
  '';
in
{
  imports = [
    ./dns-zone.nix
    ./dns-blocklists.nix
  ];

  options.services.router-technitium = {
    enable = mkEnableOption "Technitium DNS service defaults for homelab routers";

    apiKeySecretName = mkOption {
      type = types.nullOr types.str;
      default = "technitium-api-key";
      description = ''
        Optional age secret name whose path should be exported as
        TECHNITIUM_API_KEY_FILE. Set to null if the secret is managed
        elsewhere.
      '';
    };

    enableBlockLists = mkOption {
      type = types.bool;
      default = true;
      description = "Enable declarative Technitium block list synchronization.";
    };

    blockListPresets = mkOption {
      type = types.listOf types.str;
      default = [ "hagezi-normal" ];
      description = "Block list presets passed to services.router.dnsBlockLists.";
    };

    extraBlockListUrls = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional block list URLs passed to services.router.dnsBlockLists.";
    };

    blockListUpdateIntervalHours = mkOption {
      type = types.ints.between 1 168;
      default = 24;
      description = "Technitium block list refresh interval in hours.";
    };

    forceBlockListUpdateOnActivation = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to force an immediate block list refresh during activation.";
    };

    dhcpReservations = mkOption {
      type = types.attrsOf reservationModule;
      default = { };
      example = literalExpression ''
        {
          authentik-host = {
            scope = "LAN";
            macAddress = "BC:24:11:A4:01:6F";
            ipAddress = "10.10.11.70";
            hostName = "authentik-host";
            comments = "Dedicated Authentik identity host";
          };
        }
      '';
      description = ''
        Declarative Technitium DHCP reservations keyed by a stable local name.

        The current implementation is additive and safe by default: it creates
        missing reservations and leaves existing conflicting reservations in
        place instead of trying to mutate or delete them blindly.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.dhcpReservations == { } || hasApiSecret;
        message = "services.router-technitium.dhcpReservations requires a Technitium API token secret.";
      }
    ];

    services.technitium-dns-server.enable = true;

    services.router.dnsBlockLists = mkIf cfg.enableBlockLists {
      enable = true;
      presets = cfg.blockListPresets;
      extraUrls = cfg.extraBlockListUrls;
      updateIntervalHours = cfg.blockListUpdateIntervalHours;
      forceUpdateOnActivation = cfg.forceBlockListUpdateOnActivation;
    };

    environment.variables = mkIf hasApiSecret {
      TECHNITIUM_API_KEY_FILE = config.age.secrets.${secretName}.path;
    };

    environment.etc."technitium/dhcp-reservations.json" = mkIf (cfg.dhcpReservations != { }) {
      source = dhcpReservationsJson;
      mode = "0644";
    };

    systemd.services.technitium-sync-dhcp-reservations = mkIf (cfg.dhcpReservations != { }) {
      description = "Sync declarative Technitium DHCP reservations";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
      ];
      wants = [ "technitium-dns-server.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${dhcpReservationScript}
      '';
    };
  };
}
