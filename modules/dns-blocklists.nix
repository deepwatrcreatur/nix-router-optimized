{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router.dnsBlockLists;

  presetUrls = {
    stevenblack = [
      "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    ];

    oisd-big = [
      "https://big.oisd.nl/domainswild2"
    ];

    hagezi-light = [
      "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/light-onlydomains.txt"
    ];

    hagezi-normal = [
      "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/multi-onlydomains.txt"
    ];

    hagezi-pro = [
      "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro-onlydomains.txt"
    ];

    hagezi-pro-plus = [
      "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus-onlydomains.txt"
    ];

    hagezi-ultimate = [
      "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/ultimate-onlydomains.txt"
    ];

    hagezi-nrd-14d = [
      "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/nrd7.txt"
      "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/nrd14-8.txt"
    ];
  };

  selectedUrls = unique (
    concatLists (map (preset: presetUrls.${preset} or [ ]) cfg.presets)
    ++ cfg.extraUrls
  );

  ageSecrets = config.age.secrets or { };
  hasTokenBootstrap = config.systemd.services ? technitium-bootstrap-api-token;
  technitiumSecretName =
    if config.services ? router-technitium then
      config.services.router-technitium.apiKeySecretName
    else
      "technitium-api-key";
  # WHY: candidate token files in order of preference: the token maintained by
  # technitium-bootstrap-api-token (validated and re-minted when it stops
  # working), then the configured age secret.
  apiTokenPaths =
    optional hasTokenBootstrap "/var/lib/private/technitium-dns-server/nix-router-api-token"
    ++ optional (technitiumSecretName != null && ageSecrets ? ${technitiumSecretName})
      ageSecrets.${technitiumSecretName}.path;

  blockListScript = pkgs.writeShellScript "technitium-sync-blocklists" ''
    set -euo pipefail

    API_TOKEN_FILE=""
    for candidate in ${escapeShellArgs apiTokenPaths}; do
      if [ -s "$candidate" ]; then
        API_TOKEN_FILE="$candidate"
        break
      fi
    done
    if [ -z "$API_TOKEN_FILE" ]; then
      echo "Technitium API token file not found (tried: ${concatStringsSep " " apiTokenPaths}); cannot sync block lists" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$API_TOKEN_FILE")"

    # GOTCHA: Technitium reports API errors (including invalid-token) with HTTP 200,
    # so curl -f alone does not catch them.
    # See docs/router-technitium-automation.md#gotcha-technitium-reports-errors-with-http-200
    technitium_api() {
      local response status
      response="$(${pkgs.curl}/bin/curl -fsS "$@")"
      status="$(${pkgs.jq}/bin/jq -r '.status // empty' <<<"$response" 2>/dev/null || true)"
      if [ "$status" != "ok" ]; then
        echo "Technitium API call failed (status: ''${status:-unknown}): $response" >&2
        return 1
      fi
      printf '%s' "$response"
    }

    SETTINGS="$(technitium_api "http://127.0.0.1:5380/api/settings/get?token=$TOKEN")"

    ENABLE_BLOCKING="$(${pkgs.jq}/bin/jq -r '.response.enableBlocking // true' <<<"$SETTINGS")"
    ALLOW_TXT_BLOCKING_REPORT="$(${pkgs.jq}/bin/jq -r '.response.allowTxtBlockingReport // true' <<<"$SETTINGS")"
    BLOCKING_TYPE="$(${pkgs.jq}/bin/jq -r '.response.blockingType // "NxDomain"' <<<"$SETTINGS")"
    CUSTOM_BLOCKING_ADDRESSES="$(${pkgs.jq}/bin/jq -r '(.response.customBlockingAddresses // []) | join(",")' <<<"$SETTINGS")"
    BLOCKING_ANSWER_TTL="$(${pkgs.jq}/bin/jq -r '.response.blockingAnswerTtl // 30' <<<"$SETTINGS")"
    BLOCK_LIST_URLS="$(${pkgs.jq}/bin/jq -rn --argjson urls '${builtins.toJSON selectedUrls}' '$urls | join(",")')"
    # Use declarative allowlist — this is authoritative and overwrites any UI additions
    BLOCKING_BYPASS_LIST="${concatStringsSep "," cfg.allowlistDomains}"

    technitium_api -X POST \
      --data-urlencode "token=$TOKEN" \
      --data-urlencode "enableBlocking=$ENABLE_BLOCKING" \
      --data-urlencode "allowTxtBlockingReport=$ALLOW_TXT_BLOCKING_REPORT" \
      --data-urlencode "blockingBypassList=$BLOCKING_BYPASS_LIST" \
      --data-urlencode "blockingType=$BLOCKING_TYPE" \
      --data-urlencode "customBlockingAddresses=$CUSTOM_BLOCKING_ADDRESSES" \
      --data-urlencode "blockingAnswerTtl=$BLOCKING_ANSWER_TTL" \
      --data-urlencode "blockListUrls=$BLOCK_LIST_URLS" \
      --data-urlencode "blockListUpdateIntervalHours=${toString cfg.updateIntervalHours}" \
      "http://127.0.0.1:5380/api/settings/set" \
      >/dev/null

    if [ "${boolToString cfg.forceUpdateOnActivation}" = "true" ]; then
      technitium_api \
        "http://127.0.0.1:5380/api/settings/forceUpdateBlockLists?token=$TOKEN" \
        >/dev/null
    fi

    echo "Technitium block lists synchronized"
  '';
in
{
  options.services.router.dnsBlockLists = {
    enable = mkEnableOption "Declarative Technitium DNS block lists";

    presets = mkOption {
      type = types.listOf (types.enum (attrNames presetUrls));
      default = [ "hagezi-normal" ];
      example = [ "hagezi-normal" "hagezi-nrd-14d" ];
      description = "Curated block list presets to enable in Technitium.";
    };

    extraUrls = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "https://example.com/custom-blocklist.txt"
      ];
      description = "Additional block list URLs appended to the selected presets.";
    };

    updateIntervalHours = mkOption {
      type = types.ints.between 1 168;
      default = 24;
      description = "How often Technitium should refresh block lists.";
    };

    forceUpdateOnActivation = mkOption {
      type = types.bool;
      default = true;
      description = "Force an immediate block list refresh when the sync service runs.";
    };

    allowlistDomains = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "example.com" "ads.internalapp.local" ];
      description = ''
        Domains that should bypass blocking (Technitium's blockingBypassList).
        This list is authoritative — any domains added through the Technitium UI
        will be overwritten on the next rebuild and activation.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.technitium-dns-server.enable or false;
        message = "services.router.dnsBlockLists requires services.technitium-dns-server.enable = true;";
      }
      {
        assertion = selectedUrls != [ ];
        message = "services.router.dnsBlockLists must define at least one preset or extra URL.";
      }
    ];

    environment.etc."technitium/blocklists.json" = {
      text = builtins.toJSON {
        presets = cfg.presets;
        extraUrls = cfg.extraUrls;
        selectedUrls = selectedUrls;
        updateIntervalHours = cfg.updateIntervalHours;
      };
      mode = "0644";
    };

    systemd.services.technitium-sync-blocklists = {
      description = "Sync declarative Technitium DNS block lists";
      after = [
        "technitium-dns-server.service"
        "agenix.service"
      ] ++ optional hasTokenBootstrap "technitium-bootstrap-api-token.service";
      wants = [
        "technitium-dns-server.service"
      ] ++ optional hasTokenBootstrap "technitium-bootstrap-api-token.service";
      wantedBy = [ "multi-user.target" ];

      # WHY: retry if the token or Technitium is not ready yet (e.g. the
      # bootstrap token service failed transiently at boot).
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "60s";
      };

      script = ''
        ${blockListScript}
      '';
    };
  };
}
