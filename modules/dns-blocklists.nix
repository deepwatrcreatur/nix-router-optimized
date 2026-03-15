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

  apiTokenPath =
    if config.age.secrets ? technitium-api-key then
      config.age.secrets.technitium-api-key.path
    else
      "";

  blockListScript = pkgs.writeShellScript "technitium-sync-blocklists" ''
    set -euo pipefail

    if [ -z "${apiTokenPath}" ] || [ ! -f "${apiTokenPath}" ]; then
      echo "Technitium API token file not found; cannot sync block lists" >&2
      exit 1
    fi

    for i in {1..30}; do
      if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:5380/api/dns/status >/dev/null 2>&1; then
        break
      fi
      echo "Waiting for Technitium DNS Server to start..."
      sleep 2
    done

    TOKEN="$(${pkgs.coreutils}/bin/cat "${apiTokenPath}")"
    SETTINGS="$(${pkgs.curl}/bin/curl -fsS "http://127.0.0.1:5380/api/settings/get?token=$TOKEN")"

    ENABLE_BLOCKING="$(${pkgs.jq}/bin/jq -r '.response.enableBlocking // true' <<<"$SETTINGS")"
    ALLOW_TXT_BLOCKING_REPORT="$(${pkgs.jq}/bin/jq -r '.response.allowTxtBlockingReport // true' <<<"$SETTINGS")"
    BLOCKING_BYPASS_LIST="$(${pkgs.jq}/bin/jq -r '(.response.blockingBypassList // []) | join(",")' <<<"$SETTINGS")"
    BLOCKING_TYPE="$(${pkgs.jq}/bin/jq -r '.response.blockingType // "NxDomain"' <<<"$SETTINGS")"
    CUSTOM_BLOCKING_ADDRESSES="$(${pkgs.jq}/bin/jq -r '(.response.customBlockingAddresses // []) | join(",")' <<<"$SETTINGS")"
    BLOCKING_ANSWER_TTL="$(${pkgs.jq}/bin/jq -r '.response.blockingAnswerTtl // 30' <<<"$SETTINGS")"
    BLOCK_LIST_URLS="$(${pkgs.jq}/bin/jq -rn --argjson urls '${builtins.toJSON selectedUrls}' '$urls | join(",")')"

    ${pkgs.curl}/bin/curl -fsS -X POST \
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
      ${pkgs.curl}/bin/curl -fsS \
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
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.technitium-dns-server.enable or false;
        message = "services.router.dnsBlockLists requires services.technitium-dns-server.enable = true;";
      }
      {
        assertion = config.age.secrets ? technitium-api-key;
        message = "services.router.dnsBlockLists requires age.secrets.technitium-api-key to be defined;";
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
      ];
      wants = [
        "technitium-dns-server.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${blockListScript}
      '';
    };
  };
}
