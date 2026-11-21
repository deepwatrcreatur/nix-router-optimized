{
  config,
  options,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-ddns;
  hasRouterHa = options ? services.router-ha.singleActiveUnits;
  routerHaEnabled = hasRouterHa && (config.services.router-ha.enable or false);
  haUnits = [
    "router-ddns-ha-owner.service"
    "inadyn.timer"
    "inadyn.service"
  ];
  # Units the consumer listed by hand; the old documented pattern. systemctl
  # treats a bare name as ".service".
  listed = u: hasRouterHa && (elem u config.services.router-ha.singleActiveUnits || elem (removeSuffix ".service" u) config.services.router-ha.singleActiveUnits);
  manualHaUnits = listed "inadyn.service" && listed "inadyn.timer";
  runtimeDir = "/run/router-ddns";
  cloudflareIncludeFile = "${runtimeDir}/cloudflare.conf";
  cloudflareZoneName = if cfg.cloudflare.zoneName == null then "" else cfg.cloudflare.zoneName;
  cloudflareApiTokenFile =
    if cfg.cloudflare.apiTokenFile == null then "" else cfg.cloudflare.apiTokenFile;
  labelToHostname =
    label: if label == "@" then cloudflareZoneName else "${label}.${cloudflareZoneName}";
  cloudflareHostnames = (map labelToHostname cfg.cloudflare.labels) ++ cfg.cloudflare.hostnames;
  writeCloudflareInclude = pkgs.writeShellScript "router-ddns-write-cloudflare-include" ''
    set -euo pipefail

    token="$(${pkgs.coreutils}/bin/tr -d '\n' < ${escapeShellArg cloudflareApiTokenFile})"
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

    ha.singleActiveOwner = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run DDNS updates only on the VRRP MASTER. inadyn and its timer are not
        started at boot; `services.router-ha` starts both on promotion and
        stops both on backup or fault. Requires `services.router-ha.enable`.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
  {
    assertions = [
      {
        # WHY: the backup would publish the address it sees through the
        # master, and its timer keeps firing; ownership must be explicit.
        assertion = !routerHaEnabled || cfg.ha.singleActiveOwner || manualHaUnits;
        message = ''
          services.router-ddns with services.router-ha needs explicit ownership. Set
            services.router-ddns.ha.singleActiveOwner = true;
          so inadyn and inadyn.timer run only on the VRRP MASTER.
        '';
      }
      {
        assertion = cfg.ha.singleActiveOwner -> routerHaEnabled;
        message = "services.router-ddns.ha.singleActiveOwner requires services.router-ha.enable = true.";
      }
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
      ExecStartPre = mkBefore [ "+${writeCloudflareInclude}" ];
      RuntimeDirectory = "router-ddns";
      RuntimeDirectoryMode = "0750";
    };

    warnings = optional (routerHaEnabled && !cfg.ha.singleActiveOwner && manualHaUnits) ''
      services.router-ddns: inadyn units are listed in services.router-ha.singleActiveUnits
      by hand. Set services.router-ddns.ha.singleActiveOwner = true instead; it also
      keeps them from starting at boot on the backup.
    '';
  }

  (mkIf cfg.ha.singleActiveOwner {
    # INVARIANT: only router-ha notify_master starts these.
    systemd.services.inadyn = {
      wantedBy = mkForce [ ];
      after = [ "router-ddns-ha-owner.service" ];
    };
    systemd.timers.inadyn.wantedBy = mkForce [ ];

    # WHY: inadyn skips the update when its per-node cache matches the WAN
    # address, so a node returning as MASTER would leave the peer's address
    # published. Promotion clears the cache first, forcing one update.
    systemd.services.router-ddns-ha-owner = {
      description = "Force a DDNS update after VRRP promotion";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "router-ddns-clear-cache" ''
          if [ -d /var/cache/inadyn ]; then
            ${pkgs.findutils}/bin/find /var/cache/inadyn -mindepth 1 -delete
          fi
        '';
      };
    };
  })

  (optionalAttrs hasRouterHa {
    services.router-ha.singleActiveUnits = mkIf cfg.ha.singleActiveOwner haUnits;
  })
  ]);
}
