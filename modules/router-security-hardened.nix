{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-security-hardened;
  sanitizeName = name: builtins.replaceStrings [ "." ":" "@" "/" ] [ "-" "-" "-" "-" ] name;
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
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.kernelHardening.enable {
      boot.kernel.sysctl = {
        # --- System Hardening ---
        "kernel.kptr_restrict" = 2; # Hide kernel pointers
        "kernel.dmesg_restrict" = if cfg.kernelHardening.restrictDmesg then 1 else 0;
        "fs.protected_hardlinks" = 1;
        "fs.protected_symlinks" = 1;
        "fs.protected_fifos" = 2;
        "fs.protected_regular" = 2;
        "kernel.randomize_va_space" = 2; # ASLR
        "kernel.perf_event_paranoid" = 3; # Restrict perf events
        "kernel.unprivileged_bpf_disabled" = 1; # Restrict BPF

        # --- Network Hardening ---
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_rfc1337" = 1; # Protect against time-wait assassination
        "net.ipv4.conf.all.rp_filter" = 1; # Strict reverse path filtering
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.secure_redirects" = 0;
        "net.ipv4.conf.default.secure_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv4.conf.default.send_redirects" = 0;
        "net.ipv4.icmp_echo_ignore_all" = if cfg.kernelHardening.allowPing then 0 else 1;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

        # IPv6 Hardening
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.default.accept_redirects" = 0;
        "net.ipv6.conf.all.accept_source_route" = 0;
        "net.ipv6.conf.default.accept_source_route" = 0;
      };

      # Disable non-essential kernel modules
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

    (mkIf cfg.geoIpBlocking.enable {
      # 1. Define the nftables set for blocked IPs
      services.router-firewall.extraFilterTableRules = ''
        set blocked_countries {
          type ipv4_addr
          flags interval
        }
        chain geoip_block {
          ip saddr @blocked_countries drop
        }
      '';

      # 2. Jump to the geoip_block chain in the input hook
      services.router-firewall.extraInputRules = mkBefore ''
        jump geoip_block
      '';

      # 3. Systemd service to populate the set from IPDeny
      systemd.services.update-geoip-blocklist = {
        description = "Update Geo-IP blocklist from IPDeny";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          echo "Updating Geo-IP blocklist for: ${concatStringsSep ", " cfg.geoIpBlocking.blockedCountries}..."
          TMP_FILE=$(mktemp)

          # Clear the set first
          ${pkgs.nftables}/bin/nft flush set inet filter blocked_countries

          for country in ${concatStringsSep " " cfg.geoIpBlocking.blockedCountries}; do
            echo "Fetching list for $country..."
            ${pkgs.curl}/bin/curl -s "http://www.ipdeny.com/ipblocks/data/countries/$country.zone" >> "$TMP_FILE" || true
          done

          # Batch add to nftables to avoid individual command overhead
          # Filter empty lines and comments
          sed -i '/^#/d; /^$/d' "$TMP_FILE"

          while read -r line; do
            ${pkgs.nftables}/bin/nft add element inet filter blocked_countries "{ $line }"
          done < "$TMP_FILE"

          rm "$TMP_FILE"
        '';
      };

      systemd.timers.update-geoip-blocklist = {
        description = "Daily update of Geo-IP blocklist";
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    })

    (mkIf cfg.macSecurity.enable {
      services.router-firewall.extraFilterTableRules = ''
        ${concatStringsSep "\n" (
          mapAttrsToList (iface: macs: ''
            set allowed_macs_${sanitizeName iface} {
              type ether_addr
              elements = { ${concatStringsSep ", " macs} }
            }
          '') cfg.macSecurity.whitelists
        )}

        chain mac_security {
          ${concatStringsSep "\n" (
            mapAttrsToList (iface: macs: ''
              iifname "${iface}" ether saddr != @allowed_macs_${sanitizeName iface} ${
                if cfg.macSecurity.policy == "enforce" then
                  "log prefix \"MAC-REJECT: \" drop"
                else
                  "log prefix \"MAC-ALERT: \" accept"
              }
            '') cfg.macSecurity.whitelists
          )}
        }
      '';

      services.router-firewall.extraForwardRules = mkBefore ''
        jump mac_security
      '';
    })
  ]);
}
