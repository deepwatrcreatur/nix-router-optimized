{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-technitium;
  secretName = cfg.apiKeySecretName;
  bootstrapSecretName = cfg.bootstrapPasswordSecretName;
  ageSecrets = config.age.secrets or { };
  hasApiSecret = secretName != null && hasAttr secretName ageSecrets;
  hasBootstrapSecret = bootstrapSecretName != null && hasAttr bootstrapSecretName ageSecrets;
  hasTokenSource = hasApiSecret || hasBootstrapSecret;
  configuredApiTokenPath = if hasApiSecret then config.age.secrets.${secretName}.path else "/nonexistent";
  runtimeApiTokenPath = "/var/lib/private/technitium-dns-server/nix-router-api-token";
  bootstrapPasswordFile = if hasBootstrapSecret then config.age.secrets.${bootstrapSecretName}.path else "/nonexistent";
  encryptedDnsModule = types.submodule {
    options = {
      enable = mkEnableOption "native encrypted DNS features in Technitium";

      enableDnsOverTls = mkOption {
        type = types.bool;
        default = false;
        description = "Enable DNS-over-TLS (DoT) when encrypted DNS is enabled.";
      };

      enableDnsOverHttps = mkOption {
        type = types.bool;
        default = true;
        description = "Enable DNS-over-HTTPS (DoH) when encrypted DNS is enabled.";
      };

      enableDnsOverHttp3 = mkOption {
        type = types.bool;
        default = false;
        description = "Enable DNS-over-HTTPS over HTTP/3 when encrypted DNS is enabled.";
      };

      enableDnsOverQuic = mkOption {
        type = types.bool;
        default = false;
        description = "Enable DNS-over-QUIC (DoQ) when encrypted DNS is enabled.";
      };

      dnsOverTlsPort = mkOption {
        type = types.port;
        default = 853;
        description = "Port for DNS-over-TLS.";
      };

      dnsOverHttpsPort = mkOption {
        type = types.port;
        default = 443;
        description = "Port for DNS-over-HTTPS.";
      };

      dnsOverQuicPort = mkOption {
        type = types.port;
        default = 853;
        description = "Port for DNS-over-QUIC.";
      };

      webServiceTlsPort = mkOption {
        type = types.port;
        default = 53443;
        description = "Technitium web-service TLS port used to serve native DoH.";
      };

      webServiceLocalAddresses = mkOption {
        type = types.listOf types.str;
        default = [ "[::]" ];
        description = ''
          Addresses Technitium should use for its TLS-enabled web service when
          native DoH is enabled.
        '';
      };

      dnsTlsCertificatePath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "PKCS#12/PFX certificate bundle path for native DoT/DoQ listeners.";
      };

      dnsTlsCertificatePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the password for dnsTlsCertificatePath.";
      };

      webServiceTlsCertificatePath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          PKCS#12/PFX certificate bundle path for Technitium's native HTTPS
          listener used by DoH.
        '';
      };

      webServiceTlsCertificatePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the password for webServiceTlsCertificatePath.";
      };
    };
  };
  exclusionModule = types.submodule {
    options = {
      startingAddress = mkOption {
        type = types.str;
        description = "First IPv4 address in the excluded range.";
      };

      endingAddress = mkOption {
        type = types.str;
        description = "Last IPv4 address in the excluded range.";
      };
    };
  };
  scopeModule = types.submodule {
    options = {
      legacyNames = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Existing Technitium scope names that should be renamed to this declarative scope name.";
      };

      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the scope should be enabled after synchronization.";
      };

      startingAddress = mkOption {
        type = types.str;
        description = "First address in the dynamic DHCP pool.";
      };

      endingAddress = mkOption {
        type = types.str;
        description = "Last address in the dynamic DHCP pool.";
      };

      subnetMask = mkOption {
        type = types.str;
        description = "IPv4 subnet mask for the scope.";
      };

      leaseTimeDays = mkOption {
        type = types.int;
        default = 1;
        description = "Lease duration in days.";
      };

      leaseTimeHours = mkOption {
        type = types.int;
        default = 0;
        description = "Lease duration in hours.";
      };

      leaseTimeMinutes = mkOption {
        type = types.int;
        default = 0;
        description = "Lease duration in minutes.";
      };

      offerDelayTime = mkOption {
        type = types.int;
        default = 0;
        description = "Delay before sending DHCPOFFER, in milliseconds.";
      };

      pingCheckEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Technitium should ping-check an address before offering it.";
      };

      pingCheckTimeout = mkOption {
        type = types.int;
        default = 1000;
        description = "Ping timeout in milliseconds when pingCheckEnabled is true.";
      };

      pingCheckRetries = mkOption {
        type = types.int;
        default = 2;
        description = "Number of ping retries when pingCheckEnabled is true.";
      };

      domainName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "DHCP option 15 domain name for the scope.";
      };

      domainSearchList = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "DHCP option 119 search domains for the scope.";
      };

      dnsUpdates = mkOption {
        type = types.bool;
        default = true;
        description = "Whether Technitium should register dynamic DNS entries for this scope.";
      };

      dnsOverwriteForDynamicLease = mkOption {
        type = types.bool;
        default = false;
        description = "Whether dynamic leases may overwrite existing A records.";
      };

      dnsTtl = mkOption {
        type = types.int;
        default = 900;
        description = "TTL for DHCP-created DNS records.";
      };

      serverAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "DHCP next-server address, used by PXE clients.";
      };

      serverHostName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "DHCP server host name option, used by some PXE clients.";
      };

      bootFileName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "DHCP bootfile name, for example an iVentoy loader name.";
      };

      routerAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default gateway advertised to clients.";
      };

      useThisDnsServer = mkOption {
        type = types.bool;
        default = true;
        description = "Advertise the Technitium server address as DHCP option 6.";
      };

      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Explicit DNS servers advertised when useThisDnsServer is false.";
      };

      ntpServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "NTP servers advertised via DHCP option 42.";
      };

      tftpServerAddresses = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "TFTP server addresses advertised to PXE-capable clients.";
      };

      exclusions = mkOption {
        type = types.listOf exclusionModule;
        default = [ ];
        description = "Excluded address ranges that should never be handed out dynamically.";
      };

      allowOnlyReservedLeases = mkOption {
        type = types.bool;
        default = false;
        description = "When true, only reserved leases are handed out.";
      };

      blockLocallyAdministeredMacAddresses = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to deny dynamic leases to locally administered MAC addresses.";
      };

      ignoreClientIdentifierOption = mkOption {
        type = types.bool;
        default = true;
        description = "Prefer MAC address matching over DHCP option 61 when tracking leases.";
      };
    };
  };
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
  rfc2136ZoneModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Technitium zone name to enable for RFC2136 updates.";
      };

      updateNetworkACL = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.1" ];
        description = ''
          Network ACL entries allowed to submit dynamic updates for this zone.
        '';
      };

      updateSecurityPolicies = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Optional explicit Technitium update security policies. When unset, the
          module derives a TSIG-based policy suitable for forward or reverse DNS
          updates.
        '';
      };
    };
  };
  commonShellHelpers = ''
    resolve_api_token_file() {
      if [ -f "${runtimeApiTokenPath}" ]; then
        printf '%s' "${runtimeApiTokenPath}"
        return 0
      fi
      if [ -f "${configuredApiTokenPath}" ]; then
        printf '%s' "${configuredApiTokenPath}"
        return 0
      fi
      return 1
    }

    read_api_token() {
      local token_file
      token_file="$(resolve_api_token_file)" || return 1
      ${pkgs.coreutils}/bin/tr -d '\r\n' < "$token_file"
    }

    # Helper to wrap curl requests and check for Technitium API error status.
    # Technitium returns HTTP 200 even for most logical errors, so we MUST
    # parse the JSON 'status' field.
    technitium_request() {
      local response
      response="$("$@")"
      if [ "$(${pkgs.jq}/bin/jq -r '.status // "error"' <<<"$response")" != "ok" ]; then
        echo "Technitium API error: $(${pkgs.jq}/bin/jq -r '.errorMessage // .status // "unknown error"' <<<"$response")" >&2
        echo "$response" >&2
        return 1
      fi
      printf '%s' "$response"
    }

    wait_for_technitium() {
      local i
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
          return 0
        fi
        echo "Waiting for Technitium DNS Server to start..."
        ${pkgs.coreutils}/bin/sleep 2
      done

      echo "Timed out waiting for Technitium DNS Server to start" >&2
      return 1
    }

    technitium_token_is_valid() {
      local token="$1"
      local response

      response="$(${pkgs.curl}/bin/curl -fsS -G \
        --data-urlencode "token=$token" \
        "http://127.0.0.1:5380/api/settings/get" 2>/dev/null || true)"

      [ -n "$response" ] || return 1
      [ "$(${pkgs.jq}/bin/jq -r '.status // "error"' <<<"$response")" = "ok" ]
    }

    # Deterministically find the live Technitium scope name corresponding to a
    # declarative name. Handles the following cases:
    # 1. Desired name already exists (idempotent case)
    # 2. A legacy name exists (needs renaming)
    # 3. Neither exists (new scope)
    resolve_scope_name() {
      local desired_name="$1"
      local legacy_name
      local existing_name

      # First check for the desired name
      existing_name="$(${pkgs.jq}/bin/jq -r --arg desired "$desired_name" '
        .response.scopes // []
        | map(.name)
        | map(select(. == $desired))
        | first // empty
      ' <<<"$SCOPES_JSON")"
      if [ -n "$existing_name" ]; then
        printf '%s' "$existing_name"
        return 0
      fi

      # Then check for any legacy names that should be taken over
      while IFS= read -r legacy_name; do
        [ -n "$legacy_name" ] || continue
        existing_name="$(${pkgs.jq}/bin/jq -r --arg legacy "$legacy_name" '
          .response.scopes // []
          | map(.name)
          | map(select(. == $legacy))
          | first // empty
        ' <<<"$SCOPES_JSON")"
        if [ -n "$existing_name" ]; then
          printf '%s' "$existing_name"
          return 0
        fi
      done < <(${pkgs.jq}/bin/jq -r --arg desired "$desired_name" '
        .[]
        | select(.name == $desired)
        | .legacyNames[]? // empty
      ' ${dhcpScopesJson})

      return 1
    }
  '';

  apiTokenBootstrapScript = pkgs.writeShellScript "technitium-bootstrap-api-token" ''
    set -euo pipefail

    TOKEN_FILE="${runtimeApiTokenPath}"
    SEEDED_TOKEN_FILE="${configuredApiTokenPath}"
    BOOTSTRAP_PASSWORD_FILE="${bootstrapPasswordFile}"
    BOOTSTRAP_USERNAME="${cfg.bootstrapUsername}"
    TOKEN_NAME="nix-router-${config.networking.hostName}"

    ${commonShellHelpers}
    wait_for_technitium

    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$TOKEN_FILE")"
    ${pkgs.coreutils}/bin/chmod 0700 "$(${pkgs.coreutils}/bin/dirname "$TOKEN_FILE")"

    write_token_file() {
      local token="$1"
      local tmp_file

      tmp_file="$(${pkgs.coreutils}/bin/mktemp "$(${pkgs.coreutils}/bin/dirname "$TOKEN_FILE")/.api-token.XXXXXX")"
      ${pkgs.coreutils}/bin/chmod 0600 "$tmp_file"
      printf '%s\n' "$token" >"$tmp_file"
      ${pkgs.coreutils}/bin/chmod 0400 "$tmp_file"
      ${pkgs.coreutils}/bin/mv "$tmp_file" "$TOKEN_FILE"
    }

    if [ -f "$TOKEN_FILE" ]; then
      current_token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$TOKEN_FILE")"
      if [ -n "$current_token" ] && technitium_token_is_valid "$current_token"; then
        echo "Technitium automation token already valid"
        exit 0
      fi
    fi

    if [ -f "$SEEDED_TOKEN_FILE" ]; then
      seeded_token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$SEEDED_TOKEN_FILE")"
      if [ -n "$seeded_token" ] && technitium_token_is_valid "$seeded_token"; then
        write_token_file "$seeded_token"
        echo "Seeded Technitium automation token from configured secret"
        exit 0
      fi
    fi

    if [ ! -f "$BOOTSTRAP_PASSWORD_FILE" ]; then
      echo "No valid Technitium API token is available and no bootstrap password secret is configured" >&2
      exit 1
    fi

    bootstrap_password="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$BOOTSTRAP_PASSWORD_FILE")"
    if [ -z "$bootstrap_password" ]; then
      echo "Technitium bootstrap password secret is empty" >&2
      exit 1
    fi

    token_response="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "user=$BOOTSTRAP_USERNAME" \
      --data-urlencode "pass=$bootstrap_password" \
      --data-urlencode "tokenName=$TOKEN_NAME" \
      "http://127.0.0.1:5380/api/user/createToken")"
    new_token="$(${pkgs.jq}/bin/jq -r '.token // empty' <<<"$token_response")"

    if [ -z "$new_token" ]; then
      echo "Technitium bootstrap succeeded but did not return an API token" >&2
      exit 1
    fi

    write_token_file "$new_token"
    echo "Generated a node-local Technitium automation token"
  '';

  rfc2136Script = pkgs.writeShellScript "technitium-enable-rfc2136" ''
    set -euo pipefail

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
      echo "Technitium API token file not found; cannot configure RFC2136 support" >&2
      exit 1
    fi

    if [ ! -f "${cfg.rfc2136.tsigKeyFile}" ]; then
      echo "Technitium TSIG key file not found at ${cfg.rfc2136.tsigKeyFile}" >&2
      exit 1
    fi

    wait_for_technitium

    TOKEN="$(read_api_token)"
    SECRET="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${cfg.rfc2136.tsigKeyFile}")"

    echo "Registering TSIG key ${cfg.rfc2136.tsigKeyName} in Technitium..."
    technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "token=$TOKEN" \
      --data-urlencode "tsigKeys=${cfg.rfc2136.tsigKeyName}|$SECRET|${cfg.rfc2136.algorithm}" \
      "http://127.0.0.1:5380/api/settings/set" \
      >/dev/null

    ${concatMapStringsSep "\n" (zone:
      let
        defaultUpdateSecurityPolicy =
          if hasSuffix ".arpa" zone.name then
            "${cfg.rfc2136.tsigKeyName}|*.${zone.name}|PTR,DHCID"
          else
            "${cfg.rfc2136.tsigKeyName}|*.${zone.name}|A,AAAA,DHCID";
        updateSecurityPolicies = concatStringsSep ","
          (if zone.updateSecurityPolicies != [ ] then zone.updateSecurityPolicies else [ defaultUpdateSecurityPolicy ]);
      in ''
      echo "Enabling RFC2136 updates for zone ${zone.name}..."
      technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "zone=${zone.name}" \
        --data-urlencode "update=UseSpecifiedNetworkACL" \
        --data-urlencode "updateNetworkACL=${concatStringsSep "," zone.updateNetworkACL}" \
        --data-urlencode "updateSecurityPolicies=${updateSecurityPolicies}" \
        "http://127.0.0.1:5380/api/zones/options/set" \
        >/dev/null
    '') cfg.rfc2136.zones}

    echo "Technitium RFC2136 configuration synchronized"
  '';

  ntpSyncScript = pkgs.writeShellScript "technitium-sync-ntp-option" ''
    set -euo pipefail

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
      echo "Technitium API token file not found; cannot sync NTP option 42" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(read_api_token)"
    NTP_SERVERS="${concatStringsSep "," cfg.ntpServers}"

    SCOPES_JSON="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "token=$TOKEN" \
      "http://127.0.0.1:5380/api/dhcp/scopes/list")"
    SCOPES=$(echo "$SCOPES_JSON" | ${pkgs.jq}/bin/jq -r '(.response.scopes // [])[]?.name // empty')

    if [ -z "$SCOPES" ]; then
      echo "No Technitium DHCP scopes found; skipping NTP option 42 sync"
      exit 0
    fi

    while IFS= read -r scope; do
      echo "Setting DHCP option 42 (NTP=$NTP_SERVERS) on scope '$scope'"
      technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "name=$scope" \
        --data-urlencode "ntpServers=$NTP_SERVERS" \
        "http://127.0.0.1:5380/api/dhcp/scopes/set" \
        >/dev/null
    done <<< "$SCOPES"

    echo "Technitium NTP option 42 synchronized"
  '';

  listenerSyncScript = pkgs.writeShellScript "technitium-sync-listeners" ''
    set -euo pipefail

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
      echo "Technitium API token file not found; cannot sync DNS listeners" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(read_api_token)"
    DESIRED_ENDPOINTS="${concatStringsSep "," cfg.listenEndPoints}"

    SETTINGS_JSON="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "token=$TOKEN" \
      "http://127.0.0.1:5380/api/settings/get")"
    CURRENT_ENDPOINTS="$(${pkgs.jq}/bin/jq -r '
      (.response.dnsServerLocalEndPoints // [])
      | sort
      | join(",")
    ' <<<"$SETTINGS_JSON")"
    NORMALIZED_DESIRED="$(${pkgs.jq}/bin/jq -rn --arg endpoints "$DESIRED_ENDPOINTS" '
      ($endpoints | split(",") | map(select(length > 0)) | sort | join(","))
    ')"

    if [ "$CURRENT_ENDPOINTS" = "$NORMALIZED_DESIRED" ]; then
      echo "Technitium DNS listeners already synchronized"
      exit 0
    fi

    technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "token=$TOKEN" \
      --data-urlencode "dnsServerLocalEndPoints=$DESIRED_ENDPOINTS" \
      "http://127.0.0.1:5380/api/settings/set" \
      >/dev/null

    echo "Technitium DNS listeners synchronized"
  '';

  encryptedDnsSyncScript = pkgs.writeShellScript "technitium-sync-encrypted-dns" ''
    set -euo pipefail
    umask 077

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
      echo "Technitium API token file not found; cannot sync encrypted DNS settings" >&2
      exit 1
    fi

    ready=false
    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        ready=true
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    if [ "$ready" != true ]; then
      echo "Timed out after 60s waiting for Technitium DNS Server at http://127.0.0.1:5380/api/dns/status" >&2
      exit 1
    fi

    tmpdir="$(${pkgs.coreutils}/bin/mktemp -d)"
    trap '${pkgs.coreutils}/bin/rm -rf "$tmpdir"' EXIT

    copy_trimmed_secret() {
      local src="$1"
      local dest="$2"
      ${pkgs.coreutils}/bin/tr -d '\r\n' < "$src" > "$dest"
    }

    token_file="$tmpdir/token"
    copy_trimmed_secret "$(resolve_api_token_file)" "$token_file"

    cmd=(
      ${pkgs.curl}/bin/curl -fsS -X POST
      -H "Content-Type: application/x-www-form-urlencoded"
      --data-urlencode "token@$token_file"
      --data-urlencode "enableDnsOverTls=${if cfg.encryptedDns.enableDnsOverTls then "true" else "false"}"
      --data-urlencode "enableDnsOverHttps=${if cfg.encryptedDns.enableDnsOverHttps then "true" else "false"}"
      --data-urlencode "enableDnsOverHttp3=${if cfg.encryptedDns.enableDnsOverHttp3 then "true" else "false"}"
      --data-urlencode "enableDnsOverQuic=${if cfg.encryptedDns.enableDnsOverQuic then "true" else "false"}"
      --data-urlencode "dnsOverTlsPort=${toString cfg.encryptedDns.dnsOverTlsPort}"
      --data-urlencode "dnsOverHttpsPort=${toString cfg.encryptedDns.dnsOverHttpsPort}"
      --data-urlencode "dnsOverQuicPort=${toString cfg.encryptedDns.dnsOverQuicPort}"
      --data-urlencode "webServiceEnableHttp3=${if cfg.encryptedDns.enableDnsOverHttp3 then "true" else "false"}"
      --data-urlencode "webServiceTlsPort=${toString cfg.encryptedDns.webServiceTlsPort}"
      --data-urlencode "webServiceLocalAddresses=${concatStringsSep "," cfg.encryptedDns.webServiceLocalAddresses}"
      --data-urlencode "webServiceUseSelfSignedTlsCertificate=false"
    )

    maybe_add_text() {
      local key="$1"
      local value="$2"
      if [ -n "$value" ]; then
        cmd+=( --data-urlencode "$key=$value" )
      fi
    }

    maybe_add_secret_file() {
      local key="$1"
      local src="$2"
      local dest="$3"
      if [ -n "$src" ]; then
        copy_trimmed_secret "$src" "$dest"
        cmd+=( --data-urlencode "$key@$dest" )
      fi
    }

    ${optionalString (cfg.encryptedDns.enableDnsOverHttps || cfg.encryptedDns.enableDnsOverHttp3) ''
      cmd+=( --data-urlencode "webServiceEnableTls=true" )
    ''}
    ${optionalString (cfg.encryptedDns.dnsTlsCertificatePath != null) ''
      maybe_add_text "dnsTlsCertificatePath" "${toString cfg.encryptedDns.dnsTlsCertificatePath}"
    ''}
    ${optionalString (cfg.encryptedDns.webServiceTlsCertificatePath != null) ''
      maybe_add_text "webServiceTlsCertificatePath" "${toString cfg.encryptedDns.webServiceTlsCertificatePath}"
    ''}
    ${optionalString (cfg.encryptedDns.dnsTlsCertificatePasswordFile != null) ''
      maybe_add_secret_file "dnsTlsCertificatePassword" "${toString cfg.encryptedDns.dnsTlsCertificatePasswordFile}" "$tmpdir/dns-tls-password"
    ''}
    ${optionalString (cfg.encryptedDns.webServiceTlsCertificatePasswordFile != null) ''
      maybe_add_secret_file "webServiceTlsCertificatePassword" "${toString cfg.encryptedDns.webServiceTlsCertificatePasswordFile}" "$tmpdir/web-tls-password"
    ''}

    cmd+=( "http://127.0.0.1:5380/api/settings/set" )
    technitium_request "''${cmd[@]}" >/dev/null

    echo "Technitium encrypted DNS settings synchronized"
  '';

  dhcpReservationsJson = pkgs.writeText "technitium-dhcp-reservations.json" (
    builtins.toJSON (
      mapAttrsToList (name: reservation: reservation // { inherit name; }) cfg.dhcpReservations
    )
  );
  dhcpScopesJson = pkgs.writeText "technitium-dhcp-scopes.json" (
    builtins.toJSON (mapAttrsToList (name: scope: scope // { inherit name; }) cfg.scopes)
  );
  dhcpScopeScript = pkgs.writeShellScript "technitium-sync-dhcp-scopes" ''
    set -euo pipefail

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
      echo "Technitium API token file not found; cannot sync DHCP scopes" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(read_api_token)"

    SCOPES_JSON="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "token=$TOKEN" \
      "http://127.0.0.1:5380/api/dhcp/scopes/list")"

    ${pkgs.jq}/bin/jq -c '.[]' ${dhcpScopesJson} | while read -r scope; do
      desired_name="$(${pkgs.jq}/bin/jq -r '.name' <<<"$scope")"
      existing_name="$(resolve_scope_name "$desired_name" || true)"
      source_name="$desired_name"
      if [ -n "$existing_name" ]; then
        source_name="$existing_name"
      fi

      echo "Synchronizing DHCP scope '$source_name' -> '$desired_name'"

      cmd=(
        ${pkgs.curl}/bin/curl -fsS -X POST
        -H "Content-Type: application/x-www-form-urlencoded"
        --data-urlencode "token=$TOKEN"
        --data-urlencode "name=$source_name"
        --data-urlencode "startingAddress=$(${pkgs.jq}/bin/jq -r '.startingAddress' <<<"$scope")"
        --data-urlencode "endingAddress=$(${pkgs.jq}/bin/jq -r '.endingAddress' <<<"$scope")"
        --data-urlencode "subnetMask=$(${pkgs.jq}/bin/jq -r '.subnetMask' <<<"$scope")"
        --data-urlencode "leaseTimeDays=$(${pkgs.jq}/bin/jq -r '.leaseTimeDays' <<<"$scope")"
        --data-urlencode "leaseTimeHours=$(${pkgs.jq}/bin/jq -r '.leaseTimeHours' <<<"$scope")"
        --data-urlencode "leaseTimeMinutes=$(${pkgs.jq}/bin/jq -r '.leaseTimeMinutes' <<<"$scope")"
        --data-urlencode "offerDelayTime=$(${pkgs.jq}/bin/jq -r '.offerDelayTime' <<<"$scope")"
        --data-urlencode "pingCheckEnabled=$(${pkgs.jq}/bin/jq -r '.pingCheckEnabled' <<<"$scope")"
        --data-urlencode "pingCheckTimeout=$(${pkgs.jq}/bin/jq -r '.pingCheckTimeout' <<<"$scope")"
        --data-urlencode "pingCheckRetries=$(${pkgs.jq}/bin/jq -r '.pingCheckRetries' <<<"$scope")"
        --data-urlencode "dnsUpdates=$(${pkgs.jq}/bin/jq -r '.dnsUpdates' <<<"$scope")"
        --data-urlencode "dnsOverwriteForDynamicLease=$(${pkgs.jq}/bin/jq -r '.dnsOverwriteForDynamicLease' <<<"$scope")"
        --data-urlencode "dnsTtl=$(${pkgs.jq}/bin/jq -r '.dnsTtl' <<<"$scope")"
        --data-urlencode "useThisDnsServer=$(${pkgs.jq}/bin/jq -r '.useThisDnsServer' <<<"$scope")"
        --data-urlencode "allowOnlyReservedLeases=$(${pkgs.jq}/bin/jq -r '.allowOnlyReservedLeases' <<<"$scope")"
        --data-urlencode "blockLocallyAdministeredMacAddresses=$(${pkgs.jq}/bin/jq -r '.blockLocallyAdministeredMacAddresses' <<<"$scope")"
        --data-urlencode "ignoreClientIdentifierOption=$(${pkgs.jq}/bin/jq -r '.ignoreClientIdentifierOption' <<<"$scope")"
      )

      maybe_add_text() {
        local key="$1"
        local value="$2"
        if [ -n "$value" ]; then
          cmd+=( --data-urlencode "$key=$value" )
        fi
      }

      maybe_add_text "newName" "$(
        if [ "$source_name" != "$desired_name" ]; then
          printf '%s' "$desired_name"
        fi
      )"
      maybe_add_text "domainName" "$(${pkgs.jq}/bin/jq -r '.domainName // empty' <<<"$scope")"
      maybe_add_text "domainSearchList" "$(${pkgs.jq}/bin/jq -r '(.domainSearchList // []) | join(",")' <<<"$scope")"
      maybe_add_text "serverAddress" "$(${pkgs.jq}/bin/jq -r '.serverAddress // ""' <<<"$scope")"
      maybe_add_text "serverHostName" "$(${pkgs.jq}/bin/jq -r '.serverHostName // ""' <<<"$scope")"
      maybe_add_text "bootFileName" "$(${pkgs.jq}/bin/jq -r '.bootFileName // ""' <<<"$scope")"
      maybe_add_text "routerAddress" "$(${pkgs.jq}/bin/jq -r '.routerAddress // empty' <<<"$scope")"
      maybe_add_text "dnsServers" "$(${pkgs.jq}/bin/jq -r '(.dnsServers // []) | join(",")' <<<"$scope")"
      maybe_add_text "ntpServers" "$(${pkgs.jq}/bin/jq -r '(.ntpServers // []) | join(",")' <<<"$scope")"
      maybe_add_text "tftpServerAddresses" "$(${pkgs.jq}/bin/jq -r '(.tftpServerAddresses // []) | join(",")' <<<"$scope")"
      maybe_add_text "exclusions" "$(${pkgs.jq}/bin/jq -r '(.exclusions // []) | map("\(.startingAddress)|\(.endingAddress)") | join("|")' <<<"$scope")"

      cmd+=( "http://127.0.0.1:5380/api/dhcp/scopes/set" )
      technitium_request "''${cmd[@]}" >/dev/null

      SCOPES_JSON="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "token=$TOKEN" \
      "http://127.0.0.1:5380/api/dhcp/scopes/list")"
      actual_name="$(resolve_scope_name "$desired_name" || true)"
      if [ -z "$actual_name" ]; then
        echo "Declarative scope '$desired_name' did not exist before sync and is still unavailable afterwards" >&2
        exit 1
      fi
      if [ "$actual_name" != "$desired_name" ]; then
        echo "Technitium retained legacy scope name '$actual_name' for declarative scope '$desired_name'" >&2
      fi

      if [ "$(${pkgs.jq}/bin/jq -r '.enabled' <<<"$scope")" = "true" ]; then
        technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
          -H "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "token=$TOKEN" \
          --data-urlencode "name=$actual_name" \
          "http://127.0.0.1:5380/api/dhcp/scopes/enable" \
          >/dev/null
      else
        technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
          -H "Content-Type: application/x-www-form-urlencoded" \
          --data-urlencode "token=$TOKEN" \
          --data-urlencode "name=$actual_name" \
          "http://127.0.0.1:5380/api/dhcp/scopes/disable" \
          >/dev/null
      fi
    done

    echo "Technitium DHCP scopes synchronized"
  '';
  dhcpReservationScript = pkgs.writeShellScript "technitium-sync-dhcp-reservations" ''
    set -euo pipefail

    ${commonShellHelpers}

    if ! resolve_api_token_file >/dev/null; then
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

    TOKEN="$(read_api_token)"

    SCOPES_JSON="$(technitium_request ${pkgs.curl}/bin/curl -fsS -G \
      --data-urlencode "token=$TOKEN" \
      "http://127.0.0.1:5380/api/dhcp/scopes/list")"

    normalize_mac() {
      printf '%s' "$1" | ${pkgs.coreutils}/bin/tr '[:lower:]' '[:upper:]' | ${pkgs.gnused}/bin/sed 's/[:-]//g'
    }

    ${pkgs.jq}/bin/jq -c '.[]' ${dhcpReservationsJson} | while read -r reservation; do
      scope="$(${pkgs.jq}/bin/jq -r '.scope' <<<"$reservation")"
      actual_scope="$(resolve_scope_name "$scope" || true)"
      if [ -z "$actual_scope" ]; then
        echo "Unable to resolve live Technitium scope for declarative reservation scope '$scope'" >&2
        exit 1
      fi
      mac="$(${pkgs.jq}/bin/jq -r '.macAddress' <<<"$reservation")"
      ip="$(${pkgs.jq}/bin/jq -r '.ipAddress' <<<"$reservation")"
      hostname="$(${pkgs.jq}/bin/jq -r '.hostName // ""' <<<"$reservation")"
      comments="$(${pkgs.jq}/bin/jq -r '.comments // ""' <<<"$reservation")"
      name="$(${pkgs.jq}/bin/jq -r '.name' <<<"$reservation")"
      normalized_mac="$(normalize_mac "$mac")"

      existing="$(
        technitium_request ${pkgs.curl}/bin/curl -fsS -G \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "name=$actual_scope" \
        "http://127.0.0.1:5380/api/dhcp/scopes/get" \
        | ${pkgs.jq}/bin/jq -c --arg mac "$normalized_mac" '
            .response.reservedLeases // []
            | map(select(((.hardwareAddress // "") | ascii_upcase | gsub("[:-]"; "")) == $mac))
            | first
          ')"

      if [ "$existing" != "null" ]; then
        existing_ip="$(${pkgs.jq}/bin/jq -r '.address // ""' <<<"$existing")"
        existing_host="$(${pkgs.jq}/bin/jq -r '.hostName // ""' <<<"$existing")"
        if [ "$existing_ip" = "$ip" ] && [ "$existing_host" = "$hostname" ]; then
          echo "DHCP reservation $name already present ($mac -> $ip)"
          continue
        fi

        echo "Updating DHCP reservation $name: $mac $existing_ip -> $ip in scope $actual_scope"
        technitium_request ${pkgs.curl}/bin/curl -fsS -G \
          --data-urlencode "token=$TOKEN" \
          --data-urlencode "name=$actual_scope" \
          --data-urlencode "hardwareAddress=$mac" \
          "http://127.0.0.1:5380/api/dhcp/scopes/removeReservedLease" \
          >/dev/null
      fi

      echo "Adding DHCP reservation $name: $mac -> $ip in scope $actual_scope"
      technitium_request ${pkgs.curl}/bin/curl -fsS -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "name=$actual_scope" \
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

    bootstrapPasswordSecretName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Optional age secret name containing the Technitium admin password.
        When configured, the module can mint and refresh a node-local
        automation token at `${runtimeApiTokenPath}`.
      '';
    };

    bootstrapUsername = mkOption {
      type = types.str;
      default = "admin";
      description = "Technitium username used when minting an automation API token.";
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

    ntpServers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.10.1" ];
      description = ''
        NTP server addresses to advertise via DHCP option 42 on every
        managed Technitium scope.  When non-empty, a oneshot systemd
        service syncs the value into each scope via the Technitium API on
        activation.  Requires an API token secret.

        Note: this overwrites any option 42 value previously set through
        the Technitium web UI.  Leave empty to skip the sync entirely.
      '';
    };

    listenEndPoints = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "127.0.0.1:53" "10.10.10.1:53" ];
      description = ''
        Declarative DNS listener endpoints synchronized via the Technitium
        HTTP API. Leave empty to preserve Technitium's existing listener
        configuration.
      '';
    };

    encryptedDns = mkOption {
      type = encryptedDnsModule;
      default = { };
      description = ''
        Optional native encrypted DNS settings synchronized into Technitium via
        its HTTP API.
      '';
    };

    rfc2136 = {
      enable = mkEnableOption "Technitium RFC2136 dynamic update support";

      tsigKeyFile = mkOption {
        type = types.path;
        description = "File containing the RFC2136 TSIG secret.";
      };

      tsigKeyName = mkOption {
        type = types.str;
        default = "kea-ddns";
        description = "TSIG key name registered in Technitium.";
      };

      algorithm = mkOption {
        type = types.str;
        default = "hmac-sha256";
        description = "TSIG algorithm string sent to Technitium.";
      };

      zones = mkOption {
        type = types.listOf rfc2136ZoneModule;
        default = [ ];
        description = "Zones to enable for RFC2136 updates.";
      };
    };

    scopes = mkOption {
      type = types.attrsOf scopeModule;
      default = { };
      example = literalExpression ''
        {
          LAN = {
            legacyNames = [ "Default" ];
            startingAddress = "10.10.10.100";
            endingAddress = "10.10.10.250";
            subnetMask = "255.255.0.0";
            routerAddress = "10.10.10.1";
            domainName = "example.internal";
            domainSearchList = [ "example.internal" ];
            useThisDnsServer = true;
            ntpServers = [ "10.10.10.1" ];
          };
        }
      '';
      description = ''
        Declarative Technitium DHCP scope definitions keyed by the desired
        scope name. Existing scopes can be renamed into place using
        legacyNames.
      '';
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
        assertion = cfg.scopes == { } || hasTokenSource;
        message = "services.router-technitium.scopes requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = cfg.dhcpReservations == { } || hasTokenSource;
        message = "services.router-technitium.dhcpReservations requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = cfg.ntpServers == [ ] || hasTokenSource;
        message = "services.router-technitium.ntpServers requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = cfg.listenEndPoints == [ ] || hasTokenSource;
        message = "services.router-technitium.listenEndPoints requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = (!cfg.encryptedDns.enable) || hasTokenSource;
        message = "services.router-technitium.encryptedDns requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = (!cfg.rfc2136.enable) || hasTokenSource;
        message = "services.router-technitium.rfc2136 requires a Technitium API token or bootstrap password secret.";
      }
      {
        assertion = (!cfg.rfc2136.enable) || cfg.rfc2136.zones != [ ];
        message = "services.router-technitium.rfc2136.zones must not be empty when RFC2136 support is enabled.";
      }
      {
        assertion =
          (!cfg.encryptedDns.enable)
          || (!(cfg.encryptedDns.enableDnsOverTls || cfg.encryptedDns.enableDnsOverHttps || cfg.encryptedDns.enableDnsOverQuic))
          || (cfg.encryptedDns.dnsTlsCertificatePath != null && cfg.encryptedDns.dnsTlsCertificatePasswordFile != null);
        message = "Native DoT/DoH/DoQ requires dnsTlsCertificatePath and dnsTlsCertificatePasswordFile.";
      }
      {
        assertion =
          (!cfg.encryptedDns.enable)
          || (!(cfg.encryptedDns.enableDnsOverHttps || cfg.encryptedDns.enableDnsOverHttp3))
          || (cfg.encryptedDns.webServiceTlsCertificatePath != null && cfg.encryptedDns.webServiceTlsCertificatePasswordFile != null);
        message = "Native DoH/HTTP3 requires webServiceTlsCertificatePath and webServiceTlsCertificatePasswordFile.";
      }
    ];

    services.technitium-dns-server.enable = true;

    systemd.services.technitium-dns-server.environment = mkIf hasBootstrapSecret {
      DNS_SERVER_ADMIN_PASSWORD_FILE = bootstrapPasswordFile;
    };

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

    environment.etc."technitium/dhcp-scopes.json" = mkIf (cfg.scopes != { }) {
      source = dhcpScopesJson;
      mode = "0644";
    };

    systemd.services.technitium-bootstrap-api-token = mkIf hasBootstrapSecret {
      description = "Bootstrap a node-local Technitium automation token";
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
        ${apiTokenBootstrapScript}
      '';
    };

    systemd.services.technitium-sync-dhcp-scopes = mkIf (cfg.scopes != { }) {
      description = "Sync declarative Technitium DHCP scopes";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wants = [ "technitium-dns-server.service" ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${dhcpScopeScript}
      '';
    };

    systemd.services.technitium-sync-listeners = mkIf (cfg.listenEndPoints != [ ] && hasTokenSource) {
      description = "Sync Technitium DNS listener endpoints";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wants = [ "technitium-dns-server.service" ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${listenerSyncScript}
      '';
    };

    systemd.services.technitium-sync-ntp-option = mkIf (cfg.ntpServers != [ ] && hasTokenSource) {
      description = "Sync NTP server list to Technitium DHCP option 42";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
        "technitium-sync-listeners.service"
        "technitium-sync-dhcp-scopes.service"
        "technitium-sync-dhcp-reservations.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wants = [
        "technitium-dns-server.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${ntpSyncScript}
      '';
    };

    systemd.services.technitium-sync-dhcp-reservations = mkIf (cfg.dhcpReservations != { }) {
      description = "Sync declarative Technitium DHCP reservations";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
        "technitium-sync-dhcp-scopes.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wants = [ "technitium-dns-server.service" ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${dhcpReservationScript}
      '';
    };

    systemd.services.technitium-sync-encrypted-dns = mkIf (cfg.encryptedDns.enable && hasTokenSource) {
      description = "Sync Technitium encrypted DNS settings";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
        "technitium-sync-listeners.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wants = [ "technitium-dns-server.service" ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${encryptedDnsSyncScript}
      '';
    };

    systemd.services.technitium-enable-rfc2136 = mkIf cfg.rfc2136.enable {
      description = "Configure Technitium RFC2136 dynamic update support";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service"
        ++ optional (config.systemd.services ? technitium-sync-static-hosts) "technitium-sync-static-hosts.service";
      wants = [
        "technitium-dns-server.service"
      ] ++ optional hasBootstrapSecret "technitium-bootstrap-api-token.service"
        ++ optional (config.systemd.services ? technitium-sync-static-hosts) "technitium-sync-static-hosts.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${rfc2136Script}
      '';
    };
  };
}
