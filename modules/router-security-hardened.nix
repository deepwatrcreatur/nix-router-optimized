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
  sanitizeName = name: builtins.replaceStrings [ "." ":" "@" "/" ] [ "-" "-" "-" "-" ] name;
  maybeSet = ifaces: "{${concatStringsSep ", " (map (iface: "\"${iface}\"") ifaces)}}";

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
in
{
  options.services.router-security-hardened = {
    enable = mkEnableOption "router security hardening helpers";

    kernelHardening = {
      enable = mkEnableOption "strict kernel and network sysctl tuning";

      restrictDmesg = mkOption {
        type = types.bool;
        default = true;
        description = "Restrict dmesg access to root.";
      };

      allowPing = mkOption {
        type = types.bool;
        default = true;
        description = "Allow ICMP echo requests.";
      };
    };

    geoIpBlocking = {
      enable = mkEnableOption "WAN-scoped Geo-IP blocking";

      blockedCountries = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "ru"
          "cn"
          "ir"
        ];
        description = "ISO country codes whose published IPv4 ranges should be blocked on WAN ingress.";
      };
    };

    macSecurity = {
      enable = mkEnableOption "forward-path MAC whitelist checks";

      whitelists = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
        example = {
          "br-lan" = [
            "00:11:22:33:44:55"
            "AA:BB:CC:DD:EE:FF"
          ];
        };
        description = "Per-interface MAC address allowlists for forwarded traffic.";
      };

      policy = mkOption {
        type = types.enum [
          "alert"
          "enforce"
        ];
        default = "alert";
        description = "Whether unknown MACs should be logged only or logged and dropped.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.kernelHardening.enable {
      boot.kernel.sysctl = {
        "kernel.kptr_restrict" = mkForce 2;
        "kernel.dmesg_restrict" = mkForce (if cfg.kernelHardening.restrictDmesg then 1 else 0);
        "fs.protected_hardlinks" = mkForce 1;
        "fs.protected_symlinks" = mkForce 1;
        "fs.protected_fifos" = mkForce 2;
        "fs.protected_regular" = mkForce 2;
        "kernel.randomize_va_space" = mkForce 2;
        "kernel.perf_event_paranoid" = mkForce 3;
        "kernel.unprivileged_bpf_disabled" = mkForce 1;

        "net.ipv4.tcp_syncookies" = mkForce 1;
        "net.ipv4.tcp_rfc1337" = mkForce 1;
        "net.ipv4.conf.all.rp_filter" = mkForce 1;
        "net.ipv4.conf.default.rp_filter" = mkForce 1;
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
        "net.ipv6.conf.all.accept_redirects" = mkForce 0;
        "net.ipv6.conf.default.accept_redirects" = mkForce 0;
        "net.ipv6.conf.all.accept_source_route" = mkForce 0;
        "net.ipv6.conf.default.accept_source_route" = mkForce 0;
      };

      boot.blacklistedKernelModules = [
        "firewire-core"
        "thunderbolt"
        "uvcvideo"
        "bluetooth"
        "n-hdlc"
        "ax25"
        "netrom"
        "x25"
      ];
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
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail

            tmp_file="$(mktemp)"
            tmp_set="blocked_countries_new"
            success_count=0

            cleanup() {
              rm -f "$tmp_file"
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

            ${pkgs.nftables}/bin/nft add set inet filter "$tmp_set" '{ type ipv4_addr; flags interval; }'

            while read -r cidr; do
              ${pkgs.nftables}/bin/nft add element inet filter "$tmp_set" "{ $cidr }"
            done < "$tmp_file"

            ${pkgs.nftables}/bin/nft swap set inet filter blocked_countries "$tmp_set"
            ${pkgs.nftables}/bin/nft delete set inet filter "$tmp_set"
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
                      ''log prefix "MAC-ALERT: " accept''
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
  ]);
}
