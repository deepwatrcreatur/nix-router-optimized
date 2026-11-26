{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-security-hardened;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  firewallEnabled = hasRouterFirewall && (config.services.router-firewall.enable or false);
  sanitizeName = name: builtins.replaceStrings [ "." ":" "@" "/" "-" ] [ "_" "_" "_" "_" "_" ] name;
  maybeSet = ifaces: "{${concatStringsSep ", " (map (iface: "\"${iface}\"") ifaces)}}";
  defaultEgressBogonIpv4Cidrs = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.88.99.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];

  derivedWanInterfaces =
    let
      optimized = config.services.router-optimizations.interfaces or { };
    in
    mapAttrsToList (_name: iface: iface.device) (
      filterAttrs (_name: iface: iface.role == "wan") optimized
    );

  wanInterfaces =
    let
      fromFirewall = config.services.router-firewall.wanInterfaces or [ ];
    in
    if fromFirewall != [ ] then fromFirewall else derivedWanInterfaces;

  nonEmptyWhitelists = filterAttrs (_iface: macs: macs != [ ]) cfg.macSecurity.whitelists;

  rpFilterValue =
    {
      strict = 1;
      loose = 2;
      off = 0;
    }
    .${cfg.kernelHardening.rpFilter};
in
{
  options.services.router-security-hardened = {
    enable = mkEnableOption "Advanced security hardening for NixOS routers";

    kernelHardening = {
      enable = mkEnableOption "Strict kernel parameter tuning (ASLR, module restrictions)";
      restrictDmesg = mkOption {
        type = types.bool;
        default = true;
        description = "Restrict dmesg access to root user only.";
      };
      allowPing = mkOption {
        type = types.bool;
        default = true;
        description = "Allow incoming ICMP echo requests (Ping).";
      };
      rpFilter = mkOption {
        type = types.enum [
          "strict"
          "loose"
          "off"
        ];
        default = "strict";
        description = ''
          Reverse-path filtering for `net.ipv4.conf.{all,default}.rp_filter`.
          `strict` (1) drops packets whose source is not routed back out the
          interface they arrived on. Use `loose` (2) when legitimate traffic
          arrives asymmetrically: VRRP pairs, multi-WAN with policy routing, or
          a standby whose default route points at its peer. The kernel uses
          the higher of the `all` and per-interface values, so `loose` here
          also relaxes interfaces left at their default.
        '';
      };
      blacklistedModules = mkOption {
        type = types.listOf types.str;
        default = [
          "firewire-core"
          "thunderbolt"
          "uvcvideo"
          "bluetooth"
          "n-hdlc"
          "ax25"
          "netrom"
          "rose"
          "x25"
          "dccp"
          "rds"
          "tipc"
        ];
        description = ''
          Kernel modules the router never needs: legacy and rarely used network
          protocols (a socket() call would otherwise load them on demand) and
          desktop peripherals. Remove an entry if the hardware needs it, for
          example a Thunderbolt network adapter. Entries a kernel no longer
          ships (DCCP was removed in Linux 6.16) are harmless.
        '';
      };
      denyExplicitLoad = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Also refuse to load `blacklistedModules` by name or as a dependency,
          via `install <module> false` in modprobe.d. A blacklist alone only
          stops loading through module aliases, so `modprobe <module>` and
          dependent modules still load it.
        '';
      };
    };

    geoIpBlocking = {
      enable = mkEnableOption "Declarative Geo-IP blocking (requires manual IP set population)";
      blockedCountries = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "ru"
          "cn"
          "ir"
        ];
        description = "ISO country codes to block from inbound WAN traffic.";
      };
    };

    macSecurity = {
      enable = mkEnableOption "MAC address whitelisting/alerting for trusted segments";
      whitelists = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        example = {
          "enp6s16" = [
            "00:11:22:33:44:55"
            "AA:BB:CC:DD:EE:FF"
          ];
        };
        description = "Attribute set of interface names to list of allowed MAC addresses.";
      };
      policy = mkOption {
        type = types.enum [
          "alert"
          "enforce"
        ];
        default = "alert";
        description = "Whether to only log/alert on unknown MACs or strictly enforce/drop traffic.";
      };
    };

    egressBogonBlocking = {
      enable = mkEnableOption "WAN egress blocking for bogon and special-purpose IPv4 destinations";
      ipv4Cidrs = mkOption {
        type = types.listOf types.str;
        default = defaultEgressBogonIpv4Cidrs;
        description = ''
          IPv4 CIDRs blocked when traffic exits a WAN interface, covering both
          forwarded traffic and router-originated traffic. This first slice is
          intentionally IPv4-only.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.kernelHardening.enable {
      boot.kernel.sysctl = {
        # --- System Hardening ---
        "kernel.kptr_restrict" = mkForce 2; # Hide kernel pointers
        "kernel.dmesg_restrict" = mkForce (if cfg.kernelHardening.restrictDmesg then 1 else 0);
        "fs.protected_hardlinks" = mkForce 1;
        "fs.protected_symlinks" = mkForce 1;
        "fs.protected_fifos" = mkForce 2;
        "fs.protected_regular" = mkForce 2;
        "kernel.randomize_va_space" = mkForce 2; # ASLR
        "kernel.perf_event_paranoid" = mkForce 3; # Restrict perf events
        "kernel.unprivileged_bpf_disabled" = mkForce 1; # Restrict BPF
        "net.core.bpf_jit_harden" = mkForce 2; # Constant blinding for all JIT users
        "fs.suid_dumpable" = mkForce 0; # No core dumps from setuid processes

        # --- Network Hardening ---
        "net.ipv4.tcp_syncookies" = mkForce 1;
        "net.ipv4.tcp_rfc1337" = mkForce 1; # Protect against time-wait assassination
        "net.ipv4.conf.all.rp_filter" = mkForce rpFilterValue;
        "net.ipv4.conf.default.rp_filter" = mkForce rpFilterValue;
        "net.ipv4.conf.all.accept_source_route" = mkForce 0;
        "net.ipv4.conf.default.accept_source_route" = mkForce 0;
        "net.ipv4.conf.all.accept_redirects" = mkForce 0;
        "net.ipv4.conf.default.accept_redirects" = mkForce 0;
        "net.ipv4.conf.all.secure_redirects" = mkForce 0;
        "net.ipv4.conf.default.secure_redirects" = mkForce 0;
        "net.ipv4.conf.all.send_redirects" = mkForce 0;
        "net.ipv4.conf.default.send_redirects" = mkForce 0;
        "net.ipv4.icmp_echo_ignore_all" = mkForce (if cfg.kernelHardening.allowPing then 0 else 1);
        "net.ipv4.icmp_echo_ignore_broadcasts" = mkForce 1;
        "net.ipv4.icmp_ignore_bogus_error_responses" = mkForce 1;

        # IPv6 Hardening
        "net.ipv6.conf.all.accept_redirects" = mkForce 0;
        "net.ipv6.conf.default.accept_redirects" = mkForce 0;
        "net.ipv6.conf.all.accept_source_route" = mkForce 0;
        "net.ipv6.conf.default.accept_source_route" = mkForce 0;
      };

      boot.blacklistedKernelModules = cfg.kernelHardening.blacklistedModules;

      # GOTCHA: NixOS has no /bin/false, so point modprobe at a store path.
      boot.extraModprobeConfig = mkIf cfg.kernelHardening.denyExplicitLoad (
        concatMapStrings (
          module: "install ${module} ${getExe' pkgs.coreutils "false"}\n"
        ) cfg.kernelHardening.blacklistedModules
      );
    })

    (if hasRouterFirewall then
      mkIf (firewallEnabled && cfg.geoIpBlocking.enable) {
        assertions = [
          {
            assertion = cfg.geoIpBlocking.blockedCountries != [ ];
            message = "router-security-hardened: set geoIpBlocking.blockedCountries when enabling Geo-IP blocking.";
          }
          {
            assertion = wanInterfaces != [ ];
            message = "router-security-hardened: Geo-IP blocking requires at least one WAN interface from router-firewall or router-optimizations.";
          }
        ];

        services.router-firewall.extraFilterTableRules = mkAfter ''
          set blocked_countries {
            type ipv4_addr
            flags interval
          }

          chain geoip_block {
            iifname ${maybeSet wanInterfaces} ip saddr @blocked_countries drop comment "router-security-hardened WAN Geo-IP block"
          }
        '';

        services.router-firewall.extraInputEarlyRules = mkBefore ''
          jump geoip_block
        '';

        systemd.services.update-geoip-blocklist = {
          description = "Refresh Geo-IP nftables set from IPDeny over HTTPS";
          after = [
            "network-online.target"
            "nftables.service"
          ];
          wants = [ "network-online.target" ];
          partOf = [ "nftables.service" ];
          wantedBy = [
            "multi-user.target"
            "nftables.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail

            tmp_file="$(mktemp)"
            tmp_commands="$(mktemp)"
            tmp_set="blocked_countries_new"
            success_count=0

            cleanup() {
              rm -f "$tmp_file" "$tmp_commands"
              ${pkgs.nftables}/bin/nft delete set inet filter "$tmp_set" >/dev/null 2>&1 || true
            }
            trap cleanup EXIT

            for country in ${concatStringsSep " " cfg.geoIpBlocking.blockedCountries}; do
              if ${pkgs.curl}/bin/curl -fsS "https://www.ipdeny.com/ipblocks/data/countries/$country.zone" >> "$tmp_file"; then
                success_count=$((success_count + 1))
              fi
            done

            if [ "$success_count" -eq 0 ]; then
              echo "No Geo-IP country lists fetched; preserving existing nftables set." >&2
              exit 0
            fi

            ${pkgs.gnused}/bin/sed -i '/^#/d;/^$/d' "$tmp_file"

            {
              echo "add set inet filter $tmp_set { type ipv4_addr; flags interval; }"
              ${pkgs.gnused}/bin/sed "s/^/add element inet filter $tmp_set { /; s/\$/ }/" "$tmp_file"
              echo "swap set inet filter blocked_countries $tmp_set"
              echo "delete set inet filter $tmp_set"
            } > "$tmp_commands"

            ${pkgs.nftables}/bin/nft -f "$tmp_commands"
          '';
        };

        systemd.timers.update-geoip-blocklist = {
          description = "Daily Geo-IP blocklist refresh";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      }
    else
      { })

    (if hasRouterFirewall then
      mkIf (firewallEnabled && cfg.macSecurity.enable) {
        assertions = [
          {
            assertion = nonEmptyWhitelists != { };
            message = "router-security-hardened: define at least one non-empty macSecurity.whitelists entry when enabling MAC security.";
          }
          {
            assertion = allUnique (map sanitizeName (attrNames nonEmptyWhitelists));
            message = "router-security-hardened: MAC whitelist interface names must be unique after sanitization.";
          }
        ];

        services.router-firewall.extraFilterTableRules = mkAfter ''
          ${concatStringsSep "\n" (
            mapAttrsToList (
              iface: macs:
              ''
                set allowed_macs_${sanitizeName iface} {
                  type ether_addr
                  elements = { ${concatStringsSep ", " macs} }
                }
              ''
            ) nonEmptyWhitelists
          )}

          chain mac_security {
            ${concatStringsSep "\n" (
              mapAttrsToList (
                iface: _macs:
                ''
                  iifname "${iface}" ether saddr != @allowed_macs_${sanitizeName iface} ${
                    if cfg.macSecurity.policy == "enforce" then
                      ''log prefix "MAC-REJECT: " drop''
                    else
                      ''log prefix "MAC-ALERT: " return''
                  }
                ''
              ) nonEmptyWhitelists
            )}
          }
        '';

        services.router-firewall.extraForwardEarlyRules = mkBefore ''
          jump mac_security
        '';
      }
    else
      { })

    (if hasRouterFirewall then
      mkIf (firewallEnabled && cfg.egressBogonBlocking.enable) {
        assertions = [
          {
            assertion = wanInterfaces != [ ];
            message = "router-security-hardened: egressBogonBlocking requires at least one WAN interface from router-firewall or router-optimizations.";
          }
          {
            assertion = cfg.egressBogonBlocking.ipv4Cidrs != [ ];
            message = "router-security-hardened: set egressBogonBlocking.ipv4Cidrs to a non-empty list when enabling WAN egress bogon blocking.";
          }
        ];

        services.router-firewall.extraFilterTableRules = mkAfter ''
          set wan_egress_bogon_ipv4 {
            type ipv4_addr
            flags interval
            elements = { ${concatStringsSep ", " cfg.egressBogonBlocking.ipv4Cidrs} }
          }

          chain egress_bogon_block {
            oifname ${maybeSet wanInterfaces} ip daddr @wan_egress_bogon_ipv4 drop comment "router-security-hardened WAN egress bogon block"
          }
        '';

        services.router-firewall.extraForwardEarlyRules = mkBefore ''
          jump egress_bogon_block
        '';

        services.router-firewall.extraOutputEarlyRules = mkBefore ''
          jump egress_bogon_block
        '';
      }
    else
      { })
  ]);
}
