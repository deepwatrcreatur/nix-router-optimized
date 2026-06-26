{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-network-security;
  hasRouterOption = path: hasAttrByPath path options;

  optimizationInterfaces =
    if hasRouterOption [ "services" "router-optimizations" "interfaces" ] then
      config.services.router-optimizations.interfaces or { }
    else
      { };

  firewallCfg =
    if hasRouterOption [ "services" "router-firewall" ] then
      config.services.router-firewall
    else
      { };

  routedInterfaces =
    if hasRouterOption [ "services" "router-networking" "routedInterfaces" ] then
      config.services.router-networking.routedInterfaces or { }
    else
      { };

  sanitizeName = name: builtins.replaceStrings [ "." ":" "@" "/" "-" ] [ "_" "_" "_" "_" "_" ] name;

  optimizationCaptureInterfaces = mapAttrsToList (_name: iface: iface.device) optimizationInterfaces;

  firewallCaptureInterfaces =
    (firewallCfg.wanInterfaces or [ ])
    ++ (firewallCfg.lanInterfaces or [ ])
    ++ (firewallCfg.managementInterfaces or [ ])
    ++ (firewallCfg.extraTrustedInterfaces or [ ])
    ++ (firewallCfg.overlayInterfaces or [ ])
    ++ optional ((firewallCfg.tailscaleInterface or null) != null) firewallCfg.tailscaleInterface;

  derivedInterfaces = unique (filter (iface: iface != null && iface != "") (optimizationCaptureInterfaces ++ firewallCaptureInterfaces));
  effectiveInterfaces = if cfg.interfaces != [ ] then cfg.interfaces else derivedInterfaces;

  derivedHomeNetworks = mapAttrsToList (_name: iface: iface.ipv4Address) routedInterfaces;
  effectiveHomeNetworks =
    if cfg.homeNetworks != [ ] then
      cfg.homeNetworks
    else if derivedHomeNetworks != [ ] then
      derivedHomeNetworks
    else
      [ "any" ];
  eveboxInputDir = dirOf cfg.suricata.evebox.inputFile;

  snortHomeNet =
    if effectiveHomeNetworks == [ ] || effectiveHomeNetworks == [ "any" ] then
      "any"
    else if builtins.length effectiveHomeNetworks == 1 then
      builtins.head effectiveHomeNetworks
    else
      "[${concatStringsSep "," effectiveHomeNetworks}]";

  snortInterfaceArgs = concatMapStrings (iface: " -i ${escapeShellArg iface}") effectiveInterfaces;
  snortLuaArgs =
    concatMapStrings
      (chunk: " --lua ${escapeShellArg chunk}")
      (
        [
          "HOME_NET = '${snortHomeNet}'"
          "EXTERNAL_NET = 'any'"
        ]
        ++ cfg.snort.extraLuaChunks
      );

  zeekServices = listToAttrs (
    map
      (
        iface:
        let
          sanitized = sanitizeName iface;
          logDir = "/var/log/zeek/${sanitized}";
          statusDir = "/run/router-network-security/zeek";
          statusFile = "${statusDir}/${sanitized}.status";
        in
        nameValuePair "router-zeek-${sanitized}" {
          description = "Router Zeek sensor (${iface})";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [ cfg.zeek.package pkgs.coreutils ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            User = "zeek";
            Group = "zeek";
            RuntimeDirectory = "router-network-security/zeek";
            StateDirectory = "zeek";
            LogsDirectory = "zeek/${sanitized}";
            WorkingDirectory = logDir;
            ExecStart = concatStringsSep " " (
              [
                "${cfg.zeek.package}/bin/zeek"
                "-i"
                (escapeShellArg iface)
                "-U"
                (escapeShellArg statusFile)
              ]
              ++ (map escapeShellArg cfg.zeek.extraArgs)
              ++ (map escapeShellArg cfg.zeek.scripts)
            );
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectKernelLogs = true;
            ProtectHostname = true;
            ReadWritePaths = [ logDir statusDir ];
          };
        }
      )
      effectiveInterfaces
  );
in
{
  options.services.router-network-security = {
    enable = mkEnableOption "router-oriented packet security sensors";

    interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Interfaces to inspect. When empty, derived from router-firewall and
        router-optimizations interface data.
      '';
    };

    homeNetworks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Networks considered local/protected for IDS/NSM configuration. When
        empty, derived from router-networking routed interface IPv4 CIDRs.
      '';
    };

    suricata = {
      enable = mkEnableOption "Suricata network IDS";

      package = mkPackageOption pkgs "suricata" { };

      captureBackend = mkOption {
        type = types.enum [
          "pcap"
          "af-packet"
        ];
        default = "pcap";
        description = "Capture backend used for the generated Suricata interface configuration.";
      };

      enabledSources = mkOption {
        type = types.listOf types.str;
        default = [
          "abuse.ch/sslbl-blacklist"
          "abuse.ch/sslbl-c2"
          "abuse.ch/sslbl-ja3"
          "et/open"
          "etnetera/aggressive"
          "stamus/lateral"
          "oisf/trafficid"
          "tgreen/hunting"
          "pawpatrules"
          "ptrules/open"
        ];
        description = "Rule sources enabled through the upstream Suricata module.";
      };

      disabledRules = mkOption {
        type = types.listOf types.str;
        default = [
          "2270000"
          "2270001"
          "2270002"
          "2270003"
          "2270004"
        ];
        description = "Rule IDs disabled through the upstream Suricata module.";
      };

      extraSettings = mkOption {
        type = types.attrs;
        default = { };
        description = "Additional Suricata settings merged into the generated upstream settings tree.";
      };

      evebox = {
        enable = mkEnableOption "a local EveBox UI for Suricata EVE events";

        package = mkPackageOption pkgs "evebox" { };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address EveBox binds to.";
        };

        port = mkOption {
          type = types.port;
          default = 5636;
          description = "TCP port EveBox binds to.";
        };

        inputFile = mkOption {
          type = types.str;
          default = "/var/log/suricata/eve.json";
          description = "Suricata EVE JSON file EveBox tails.";
        };

        noAuth = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Disable EveBox's built-in authentication. This first slice assumes
            EveBox stays bound to localhost and is exposed only through a
            consumer-managed trusted reverse proxy path.
          '';
        };

        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional arguments appended to the EveBox server command.";
        };
      };
    };

    snort = {
      enable = mkEnableOption "Snort 3 network IDS/IPS sensor";

      package = mkPackageOption pkgs "snort" { };

      profile = mkOption {
        type = types.enum [
          "balanced"
          "connectivity"
          "max_detect"
          "security"
          "inline"
        ];
        default = "security";
        description = "Base Snort configuration profile from the packaged defaults.";
      };

      daqMode = mkOption {
        type = types.enum [
          "passive"
          "inline"
          "read-file"
        ];
        default = "passive";
        description = "DAQ mode passed to Snort.";
      };

      alertMode = mkOption {
        type = types.str;
        default = "alert_fast";
        description = "Snort alert mode passed via `-A`.";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional arguments appended to the Snort command line.";
      };

      extraLuaChunks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra `--lua` chunks appended after the generated HOME_NET/EXTERNAL_NET overrides.";
      };
    };

    zeek = {
      enable = mkEnableOption "Zeek network security monitor";

      package = mkPackageOption pkgs "zeek" { };

      scripts = mkOption {
        type = types.listOf types.str;
        default = [ "local" ];
        description = "Zeek scripts loaded after the interface and status-file arguments.";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional Zeek arguments prepended before the script list.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.suricata.enable || cfg.snort.enable || cfg.zeek.enable;
        message = "router-network-security: enable at least one of suricata, snort, or zeek.";
      }
      {
        assertion = !cfg.suricata.evebox.enable || cfg.suricata.enable;
        message = "router-network-security: services.router-network-security.suricata.evebox requires Suricata to be enabled.";
      }
      {
        assertion = effectiveInterfaces != [ ];
        message = "router-network-security: set interfaces explicitly or provide router-firewall/router-optimizations interface data to derive them.";
      }
    ];

    warnings = optionals (cfg.suricata.enable && cfg.snort.enable) [
      "router-network-security: Suricata and Snort are both enabled. Concurrent full-packet engines on the same interfaces can be expensive and may require consumer-side tuning."
    ];

    services.suricata = mkIf cfg.suricata.enable {
      enable = true;
      package = cfg.suricata.package;
      inherit (cfg.suricata) enabledSources disabledRules;
      settings =
        {
          vars.address-groups.HOME_NET = effectiveHomeNetworks;
        }
        // optionalAttrs (cfg.suricata.captureBackend == "pcap") {
          pcap = map (iface: { interface = iface; }) effectiveInterfaces;
        }
        // optionalAttrs (cfg.suricata.captureBackend == "af-packet") {
          af-packet = map (
            iface:
            {
              interface = iface;
              cluster-id = "99";
              cluster-type = "cluster_flow";
              defrag = "yes";
            }
          ) effectiveInterfaces;
        }
        // cfg.suricata.extraSettings;
    };

    users.groups.snort = mkIf cfg.snort.enable { };
    users.users.snort = mkIf cfg.snort.enable {
      isSystemUser = true;
      group = "snort";
    };

    users.groups.zeek = mkIf cfg.zeek.enable { };
    users.users.zeek = mkIf cfg.zeek.enable {
      isSystemUser = true;
      group = "zeek";
    };

    users.groups.evebox = mkIf cfg.suricata.evebox.enable { };
    users.users.evebox = mkIf cfg.suricata.evebox.enable {
      isSystemUser = true;
      group = "evebox";
      extraGroups = [ "suricata" ];
    };

    systemd.services = mkMerge [
      (mkIf cfg.suricata.evebox.enable {
        router-evebox = {
          description = "Router EveBox server";
          after = [ "network-online.target" "suricata.service" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [ cfg.suricata.evebox.package ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            User = "evebox";
            Group = "evebox";
            StateDirectory = "evebox";
            WorkingDirectory = "/var/lib/evebox";
            ExecStart = concatStringsSep " " (
              [
                "${cfg.suricata.evebox.package}/bin/evebox"
                "--data-directory"
                "/var/lib/evebox"
                "server"
                "--sqlite"
                "--no-tls"
                "--host"
                (escapeShellArg cfg.suricata.evebox.host)
                "--port"
                (toString cfg.suricata.evebox.port)
                "--input"
                (escapeShellArg cfg.suricata.evebox.inputFile)
                "--end"
              ]
              ++ optionals cfg.suricata.evebox.noAuth [ "--no-auth" ]
              ++ map escapeShellArg cfg.suricata.evebox.extraArgs
            );
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectKernelLogs = true;
            ProtectHostname = true;
            ReadOnlyPaths = [ eveboxInputDir ];
            ReadWritePaths = [ "/var/lib/evebox" ];
          };
        };
      })
      (mkIf cfg.snort.enable {
        router-snort = {
          description = "Router Snort sensor";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [ cfg.snort.package ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            User = "snort";
            Group = "snort";
            LogsDirectory = "router-snort";
            RuntimeDirectory = "router-snort";
            StateDirectory = "router-snort";
            ExecStartPre = "!${cfg.snort.package}/bin/snort -T -c ${cfg.snort.package}/etc/snort/${cfg.snort.profile}.lua --daq-dir ${cfg.snort.package}/lib/snort/daq --daq-mode ${cfg.snort.daqMode}${snortInterfaceArgs} -A ${cfg.snort.alertMode} -l /var/log/router-snort${snortLuaArgs}";
            ExecStart = "!${cfg.snort.package}/bin/snort -c ${cfg.snort.package}/etc/snort/${cfg.snort.profile}.lua --daq-dir ${cfg.snort.package}/lib/snort/daq --daq-mode ${cfg.snort.daqMode}${snortInterfaceArgs} -A ${cfg.snort.alertMode} -l /var/log/router-snort${snortLuaArgs}${optionalString (cfg.snort.extraArgs != [ ]) " ${escapeShellArgs cfg.snort.extraArgs}"}";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            ProtectKernelLogs = true;
            ProtectHostname = true;
            ReadOnlyPaths = [ "${cfg.snort.package}/etc/snort" ];
            ReadWritePaths = [ "/var/log/router-snort" ];
          };
        };
      })
      (mkIf cfg.zeek.enable zeekServices)
    ];
  };
}
