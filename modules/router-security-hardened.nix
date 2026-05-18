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
        "kernel.kptr_restrict" = mkForce 2; # Hide kernel pointers
        "kernel.dmesg_restrict" = mkForce (if cfg.kernelHardening.restrictDmesg then 1 else 0);
        "fs.protected_hardlinks" = mkForce 1;
        "fs.protected_symlinks" = mkForce 1;
        "fs.protected_fifos" = mkForce 2;
        "fs.protected_regular" = mkForce 2;
        "kernel.randomize_va_space" = mkForce 2; # ASLR
        "kernel.perf_event_paranoid" = mkForce 3; # Restrict perf events
        "kernel.unprivileged_bpf_disabled" = mkForce 1; # Restrict BPF

        # --- Network Hardening ---
        "net.ipv4.tcp_syncookies" = mkForce 1;
        "net.ipv4.tcp_rfc1337" = mkForce 1; # Protect against time-wait assassination
        "net.ipv4.conf.all.rp_filter" = mkForce 1; # Strict reverse path filtering
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

        # IPv6 Hardening
        "net.ipv6.conf.all.accept_redirects" = mkForce 0;
        "net.ipv6.conf.default.accept_redirects" = mkForce 0;
        "net.ipv6.conf.all.accept_source_route" = mkForce 0;
        "net.ipv6.conf.default.accept_source_route" = mkForce 0;
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

    (if hasRouterFirewall then mkIf (firewallEnabled && cfg.geoIpBlocking.enable) {
      # 1. Define the nftables set for blocked IPs
      services.router-firewall.extraFilterTableRules = ''
        set blocked_countries {
          type ipv4_addr
          flags interval
        }
        chain geoip_block {
          ${
            let
              # Try to get WAN interfaces from firewall config or optimizations
              fwWan = config.services.router-firewall.wanInterfaces or [ ];
              optWan = mapAttrsToList (_name: iface: iface.device) (
                filterAttrs (_name: iface: iface.role == "wan") (
                  config.services.router-optimizations.interfaces or { }
                )
              );
              wanIfaces = if fwWan != [ ] then fwWan else optWan;
              maybeSet = ifaces: if ifaces == [ ] then "" else "{${concatStringsSep ", " (map (i: "\"${i}\"") ifaces)}}";
            in
            if wanIfaces != [ ] then "iifname ${maybeSet wanIfaces} ip saddr @blocked_countries drop" else ""
          }
        }
      '';

      # 2. Jump to the geoip_block chain in the input hook
      services.router-firewall.extraInputEarlyRules = mkBefore ''
        jump geoip_block
      '';

      # 3. Systemd service to populate the set from IPDeny (via HTTPS)
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
          NFT_BATCH=$(mktemp)
          SUCCESS_COUNT=0

          for country in ${concatStringsSep " " cfg.geoIpBlocking.blockedCountries}; do
            echo "Fetching list for $country..."
            if ${pkgs.curl}/bin/curl -s -f "https://www.ipdeny.com/ipblocks/data/countries/$country.zone" >> "$TMP_FILE"; then
              SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
              echo "Warning: Failed to fetch list for $country"
            fi
          done

          if [ "$SUCCESS_COUNT" -gt 0 ]; then
            # Filter empty lines and comments
            sed -i '/^#/d; /^$/d' "$TMP_FILE"

            # Build a single nft batch file so the flush + reload happens as one
            # validated transaction rather than by mutating the live set
            # incrementally.
            cat > "$NFT_BATCH" <<'EOF'
flush set inet filter blocked_countries
EOF

            while read -r line; do
              printf 'add element inet filter blocked_countries { %s }\n' "$line" >> "$NFT_BATCH"
            done < "$TMP_FILE"

            ${pkgs.nftables}/bin/nft -c -f "$NFT_BATCH"
            ${pkgs.nftables}/bin/nft -f "$NFT_BATCH"

            echo "Successfully updated Geo-IP blocklist with $SUCCESS_COUNT countries."
          else
            echo "Error: No country lists could be fetched. Keeping existing blocklist."
          fi

          rm "$TMP_FILE"
          rm "$NFT_BATCH"
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
    } else { })

    (if hasRouterFirewall then mkIf (firewallEnabled && cfg.macSecurity.enable) {
      services.router-firewall.extraFilterTableRules = ''
        ${concatStringsSep "\n" (
          mapAttrsToList (iface: macs: ''
            set allowed_macs_${sanitizeName iface} {
              type ether_addr
              ${optionalString (macs != [ ]) "elements = { ${concatStringsSep ", " macs} }"}
            }
          '') (filterAttrs (n: v: v != [ ]) cfg.macSecurity.whitelists)
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
            '') (filterAttrs (n: v: v != [ ]) cfg.macSecurity.whitelists)
          )}
        }
      '';

      services.router-firewall.extraForwardEarlyRules = mkBefore ''
        # MAC security for forwarded traffic
        jump mac_security
      '';
    } else { })
  ]);
}
