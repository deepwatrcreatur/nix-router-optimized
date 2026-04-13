{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-ddns;
  runtimeDir = "/run/router-ddns";
  cloudflareIncludeFile = "${runtimeDir}/cloudflare.conf";
  cloudflareZoneName = cfg.cloudflare.zoneName or "";
  labelToHostname =
    label: if label == "@" then cloudflareZoneName else "${label}.${cloudflareZoneName}";
  cloudflareHostnames = (map labelToHostname cfg.cloudflare.labels) ++ cfg.cloudflare.hostnames;
  writeCloudflareInclude = pkgs.writeShellScript "router-ddns-write-cloudflare-include" ''
    set -euo pipefail

    token="$(${pkgs.coreutils}/bin/tr -d '\n' < ${escapeShellArg cfg.cloudflare.apiTokenFile})"
    test -n "$token"

    tmp="$(${pkgs.coreutils}/bin/mktemp ${escapeShellArg "${runtimeDir}/cloudflare.conf.XXXXXX"})"
    ${pkgs.coreutils}/bin/chown root:${escapeShellArg config.services.inadyn.group} "$tmp"
    ${pkgs.coreutils}/bin/chmod 0640 "$tmp"
    ${pkgs.coreutils}/bin/printf 'password = "%s"\n' "$token" > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" ${escapeShellArg cloudflareIncludeFile}
  '';
in
{
  options.services.router-ddns = {
    enable = mkEnableOption "router-oriented dynamic DNS using inadyn";

    interval = mkOption {
      type = types.str;
      default = "*-*-* *:0/5:00";
      description = "Systemd calendar expression for how often inadyn checks the public address.";
    };

    logLevel = mkOption {
      type = types.enum [
        "none"
        "err"
        "warning"
        "info"
        "notice"
        "debug"
      ];
      default = "notice";
      description = "inadyn log level.";
    };

    allowIPv6 = mkOption {
      type = types.bool;
      default = config.networking.enableIPv6;
      defaultText = literalExpression "config.networking.enableIPv6";
      description = "Whether inadyn should update IPv6 records when the provider supports it.";
    };

    cloudflare = {
      zoneName = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "example.com";
        description = "Cloudflare zone name. Existing router inventory uses router.ddnsServices labels under this zone.";
      };

      labels = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "@"
          "homelab"
          "paperless"
        ];
        description = ''
          DNS labels under zoneName to update. Use "@" for the zone apex.
          This matches the existing unified-nix-configuration router.ddnsServices shape.
        '';
      };

      hostnames = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "service.example.com" ];
        description = "Additional fully qualified Cloudflare hostnames to update.";
      };

      apiTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Runtime file containing a raw Cloudflare API token. The module converts
          it into an inadyn include file at service start so the token is not
          embedded in the Nix store.
        '';
      };

      ttl = mkOption {
        type = types.ints.positive;
        default = 3600;
        description = "Cloudflare record TTL in seconds. Use 1 for Cloudflare automatic TTL.";
      };

      proxied = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Cloudflare should proxy the managed DNS records.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cloudflare.zoneName != null;
        message = "services.router-ddns.cloudflare.zoneName must be set.";
      }
      {
        assertion = cfg.cloudflare.apiTokenFile != null;
        message = "services.router-ddns.cloudflare.apiTokenFile must be set.";
      }
      {
        assertion = cloudflareHostnames != [ ];
        message = "services.router-ddns.cloudflare.labels or hostnames must include at least one DNS name.";
      }
    ];

    services.inadyn = {
      enable = true;
      interval = cfg.interval;
      logLevel = cfg.logLevel;
      settings = {
        allow-ipv6 = cfg.allowIPv6;
        provider."default@cloudflare.com" = {
          username = cloudflareZoneName;
          include = cloudflareIncludeFile;
          hostname = cloudflareHostnames;
          ttl = cfg.cloudflare.ttl;
          proxied = cfg.cloudflare.proxied;
        };
      };
    };

    systemd.services.inadyn.serviceConfig = {
      ExecStartPre = "+${writeCloudflareInclude}";
      RuntimeDirectory = "router-ddns";
      RuntimeDirectoryMode = "0750";
    };
  };
}
