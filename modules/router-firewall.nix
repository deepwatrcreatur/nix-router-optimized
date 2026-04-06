{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-firewall;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };
  routedIfaces = config.services.router-networking.routedInterfaces or { };

  interfaceByRole = role:
    mapAttrsToList (_name: iface: iface.device) (
      filterAttrs (_name: iface: iface.role == role) optimizationInterfaces
    );

  wanInterfaces =
    if cfg.wanInterfaces != [ ] then cfg.wanInterfaces else interfaceByRole "wan";

  lanInterfaces =
    if cfg.lanInterfaces != [ ] then cfg.lanInterfaces else interfaceByRole "lan";

  managementInterfaces =
    if cfg.managementInterfaces != [ ] then cfg.managementInterfaces else interfaceByRole "management";

  trustedInterfaces = unique (cfg.extraTrustedInterfaces ++ lanInterfaces ++ managementInterfaces);
  allRouterInterfaces = unique (wanInterfaces ++ trustedInterfaces);
  effectiveHairpinCidrs =
    if cfg.hairpinNat.ipv4Cidrs != [ ] then
      cfg.hairpinNat.ipv4Cidrs
    else
      mapAttrsToList (_name: iface: iface.ipv4Address) routedIfaces;

  quotedSet = ifaces: concatStringsSep ", " (map (iface: "\"${iface}\"") ifaces);
  maybeSet = ifaces: if ifaces == [ ] then "" else "{${quotedSet ifaces}}";
  tcpPortSet = ports: concatStringsSep ", " (map toString ports);
  cidrSet = cidrs: concatStringsSep ", " cidrs;

  mkInputRule = ifaces: rule:
    optionalString (ifaces != [ ]) ''
      iifname ${maybeSet ifaces} ${rule}
    '';

  mkForwardRule = srcIfaces: dstIfaces: suffix:
    optionalString (srcIfaces != [ ] && dstIfaces != [ ]) ''
      iifname ${maybeSet srcIfaces} oifname ${maybeSet dstIfaces} ${suffix}
    '';
in
{
  options.services.router-firewall = {
    enable = mkEnableOption "role-aware nftables policy for routed NixOS routers";

    autoInterfacesFromOptimizations = mkOption {
      type = types.bool;
      default = true;
      description = "Derive WAN/LAN/management interfaces from services.router-optimizations.interfaces when explicit lists are not set.";
    };

    wanInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Explicit WAN interfaces. Leave empty to derive from router-optimizations.";
    };

    lanInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Explicit LAN interfaces. Leave empty to derive from router-optimizations.";
    };

    managementInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Explicit management interfaces. Leave empty to derive from router-optimizations.";
    };

    extraTrustedInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional trusted router-facing interfaces.";
    };

    tailscaleInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional Tailscale interface to trust and route through.";
    };

    allowSsh = mkOption {
      type = types.bool;
      default = true;
      description = "Allow SSH from trusted interfaces.";
    };

    dnsInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Interfaces allowed to reach router DNS/DHCP services. Defaults to trusted interfaces.";
    };

    dnsTcpPorts = mkOption {
      type = types.listOf types.int;
      default = [ 53 ];
      description = "TCP DNS-like ports exposed on dnsInterfaces.";
    };

    dnsUdpPorts = mkOption {
      type = types.listOf types.int;
      default = [ 53 67 68 547 ];
      description = "UDP DNS/DHCP-like ports exposed on dnsInterfaces.";
    };

    lanToWan = mkOption {
      type = types.bool;
      default = true;
      description = "Allow LAN interfaces to forward to WAN.";
    };

    managementToWan = mkOption {
      type = types.bool;
      default = true;
      description = "Allow management interfaces to forward to WAN.";
    };

    allowTrustedInterconnect = mkOption {
      type = types.bool;
      default = true;
      description = "Allow forwarding between trusted interfaces such as LAN and management.";
    };

    enableIpv6 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable IPv6 ICMP and DHCPv6 allowances.";
    };

    wanUdpPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "UDP ports exposed on WAN, for example WireGuard or Tailscale.";
    };

    wanTcpPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "TCP ports exposed on WAN, for example 80/443.";
    };

    trustedTcpPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "TCP ports exposed on trusted interfaces.";
    };

    trustedUdpPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "UDP ports exposed on trusted interfaces.";
    };

    inputLogPrefix = mkOption {
      type = types.str;
      default = "FW-INPUT-DROP ";
      description = "Prefix for logged input drops.";
    };

    forwardLogPrefix = mkOption {
      type = types.str;
      default = "FW-FORWARD-DROP ";
      description = "Prefix for logged forward drops.";
    };

    invalidLogPrefix = mkOption {
      type = types.str;
      default = "FW-INVALID ";
      description = "Prefix for logged invalid forwarded packets.";
    };

    extraInputRules = mkOption {
      type = types.lines;
      default = "";
      description = "Extra nftables input-chain rules appended before final drop.";
    };

    extraForwardRules = mkOption {
      type = types.lines;
      default = "";
      description = "Extra nftables forward-chain rules appended before final drop.";
    };

    enableIpv4Masquerade = mkOption {
      type = types.bool;
      default = true;
      description = "Masquerade IPv4 traffic exiting WAN interfaces.";
    };

    hairpinNat.enable = mkEnableOption "IPv4 hairpin NAT for trusted segments";

    hairpinNat.ipv4Cidrs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        IPv4 CIDRs eligible for trusted-to-trusted hairpin masquerading. When
        left empty, routed interface IPv4 CIDRs from router-networking are used.
      '';
    };

    tcpMssClamp.enable = mkEnableOption "TCP MSS clamping on forwarded WAN traffic";

    tcpMssClamp.value = mkOption {
      type = types.oneOf [ types.str types.int ];
      default = "rt mtu";
      description = ''
        MSS clamp value. Use `"rt mtu"` for path-MTU-aware clamping, or an
        explicit MSS integer such as `1452`.
      '';
    };

    flowtable.enable = mkEnableOption "nftables flowtable acceleration" // {
      default = true;
    };

    flowtable.interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Interfaces used by the nftables flowtable. Defaults to all router interfaces.";
    };

    loggingRateLimit = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Rate-limit drop logging to prevent log flooding under port scans or attacks.";
      };

      rate = mkOption {
        type = types.str;
        default = "5/second";
        example = "10/minute";
        description = "nftables rate expression for log lines (e.g., \"5/second\", \"10/minute\").";
      };

      burst = mkOption {
        type = types.int;
        default = 10;
        description = "Burst allowance above the rate limit before logs are suppressed.";
      };
    };

    flowLogging = {
      enable = mkEnableOption "high-performance flow logging via NFLOG (ulogd)";
      group = mkOption {
        type = types.int;
        default = 1;
        description = "NFLOG group ID for flow logging.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.autoInterfacesFromOptimizations || wanInterfaces != [ ];
        message = "router-firewall needs at least one WAN interface, either explicit or derived from router-optimizations.";
      }
      {
        assertion = !(config.services.nftables-fasttrack.enable or false);
        message = "router-firewall and nftables-fasttrack cannot both be enabled. Disable nftables-fasttrack when using router-firewall.";
      }
    ];

    networking.nftables.enable = true;
    networking.firewall.enable = false;

    networking.nftables.ruleset = ''
      table inet mangle {
        chain forward {
          type filter hook forward priority mangle; policy accept;

          ${optionalString (cfg.tcpMssClamp.enable && trustedInterfaces != [ ] && wanInterfaces != [ ]) ''
            iifname ${maybeSet trustedInterfaces} oifname ${maybeSet wanInterfaces} tcp flags syn tcp option maxseg size set ${toString cfg.tcpMssClamp.value}
            iifname ${maybeSet wanInterfaces} oifname ${maybeSet trustedInterfaces} tcp flags syn tcp option maxseg size set ${toString cfg.tcpMssClamp.value}
          ''}
        }
      }

      table inet filter {
        ${optionalString cfg.flowLogging.enable ''
          chain flow-logger {
            log group ${toString cfg.flowLogging.group}
          }
        ''}

        chain WAN_LOCAL {
          ${optionalString cfg.enableIpv6 ''
            udp dport 546 accept comment "DHCPv6 client"
          ''}
          ${optionalString (cfg.wanTcpPorts != [ ]) ''
            tcp dport {${tcpPortSet cfg.wanTcpPorts}} accept
          ''}
          ${optionalString (cfg.wanUdpPorts != [ ]) ''
            udp dport {${tcpPortSet cfg.wanUdpPorts}} accept
          ''}
        }

        chain LAN_LOCAL {
          ${optionalString cfg.allowSsh ''
            tcp dport 22 accept
          ''}
          ${
            let dnsIfaces = if cfg.dnsInterfaces != [ ] then cfg.dnsInterfaces else trustedInterfaces;
            in optionalString (elem "lan" (mapAttrsToList (_name: iface: iface.role) (filterAttrs (n: v: elem v.device lanInterfaces) optimizationInterfaces))) (
              optionalString (cfg.dnsUdpPorts != [ ]) ''
                udp dport {${tcpPortSet cfg.dnsUdpPorts}} accept
              '' + optionalString (elem 67 cfg.dnsUdpPorts && elem 68 cfg.dnsUdpPorts) ''
                udp sport {67, 68} accept
              '' + optionalString (cfg.dnsTcpPorts != [ ]) ''
                tcp dport {${tcpPortSet cfg.dnsTcpPorts}} accept
              ''
            )
          }
          ${optionalString (cfg.trustedTcpPorts != [ ]) ''
            tcp dport {${tcpPortSet cfg.trustedTcpPorts}} accept
          ''}
          ${optionalString (cfg.trustedUdpPorts != [ ]) ''
            udp dport {${tcpPortSet cfg.trustedUdpPorts}} accept
          ''}
        }

        chain MGMT_LOCAL {
          ${optionalString cfg.allowSsh ''
            tcp dport 22 accept
          ''}
          ${
            let dnsIfaces = if cfg.dnsInterfaces != [ ] then cfg.dnsInterfaces else trustedInterfaces;
            in optionalString (elem "management" (mapAttrsToList (_name: iface: iface.role) (filterAttrs (n: v: elem v.device managementInterfaces) optimizationInterfaces))) (
              optionalString (cfg.dnsUdpPorts != [ ]) ''
                udp dport {${tcpPortSet cfg.dnsUdpPorts}} accept
              '' + optionalString (elem 67 cfg.dnsUdpPorts && elem 68 cfg.dnsUdpPorts) ''
                udp sport {67, 68} accept
              '' + optionalString (cfg.dnsTcpPorts != [ ]) ''
                tcp dport {${tcpPortSet cfg.dnsTcpPorts}} accept
              ''
            )
          }
          ${optionalString (cfg.trustedTcpPorts != [ ]) ''
            tcp dport {${tcpPortSet cfg.trustedTcpPorts}} accept
          ''}
          ${optionalString (cfg.trustedUdpPorts != [ ]) ''
            udp dport {${tcpPortSet cfg.trustedUdpPorts}} accept
          ''}
        }

        chain WAN_IN {
          # Default drop via forward chain policy
        }

        chain LAN_IN {
          ${optionalString cfg.lanToWan (mkForwardRule lanInterfaces wanInterfaces "accept")}
          ${
            if cfg.allowTrustedInterconnect && trustedInterfaces != [ ] then
              ''
                iifname ${maybeSet lanInterfaces} oifname ${maybeSet trustedInterfaces} accept
              ''
            else
              ""
          }
        }

        chain MGMT_IN {
          ${optionalString cfg.managementToWan (mkForwardRule managementInterfaces wanInterfaces "accept")}
          ${
            if cfg.allowTrustedInterconnect && trustedInterfaces != [ ] then
              ''
                iifname ${maybeSet managementInterfaces} oifname ${maybeSet trustedInterfaces} accept
              ''
            else
              ""
          }
        }

        chain input {
          type filter hook input priority 0; policy drop;

          ${optionalString cfg.flowLogging.enable "jump flow-logger"}
          ct state {established, related} accept
          iifname "lo" accept

          ip protocol icmp accept
          ${optionalString cfg.enableIpv6 "ip6 nexthdr icmpv6 accept"}

          ${optionalString (wanInterfaces != [ ]) "iifname ${maybeSet wanInterfaces} jump WAN_LOCAL"}
          ${optionalString (lanInterfaces != [ ]) "iifname ${maybeSet lanInterfaces} jump LAN_LOCAL"}
          ${optionalString (managementInterfaces != [ ]) "iifname ${maybeSet managementInterfaces} jump MGMT_LOCAL"}

          ${optionalString (cfg.tailscaleInterface != null) ''
            iifname "${cfg.tailscaleInterface}" accept
          ''}

          ${cfg.extraInputRules}

          ${if cfg.loggingRateLimit.enable then ''
            limit rate ${cfg.loggingRateLimit.rate} burst ${toString cfg.loggingRateLimit.burst} packets log prefix "${cfg.inputLogPrefix}" level info flags all
          '' else ''
            log prefix "${cfg.inputLogPrefix}" level info flags all
          ''}
          drop
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          ${optionalString cfg.flowLogging.enable "jump flow-logger"}
          ct state {established, related} accept
          ct state invalid log prefix "${cfg.invalidLogPrefix}" level info flags all
          ct state invalid drop

          ${optionalString (wanInterfaces != [ ]) "iifname ${maybeSet wanInterfaces} jump WAN_IN"}
          ${optionalString (lanInterfaces != [ ]) "iifname ${maybeSet lanInterfaces} jump LAN_IN"}
          ${optionalString (managementInterfaces != [ ]) "iifname ${maybeSet managementInterfaces} jump MGMT_IN"}

          ${optionalString (cfg.tailscaleInterface != null && allRouterInterfaces != [ ]) ''
            iifname "${cfg.tailscaleInterface}" oifname ${maybeSet allRouterInterfaces} accept
            iifname ${maybeSet trustedInterfaces} oifname "${cfg.tailscaleInterface}" accept
          ''}

          ${cfg.extraForwardRules}

          ${if cfg.loggingRateLimit.enable then ''
            limit rate ${cfg.loggingRateLimit.rate} burst ${toString cfg.loggingRateLimit.burst} packets log prefix "${cfg.forwardLogPrefix}" level info flags all
          '' else ''
            log prefix "${cfg.forwardLogPrefix}" level info flags all
          ''}
          drop
        }

        chain output {
          type filter hook output priority 0; policy accept;
        }
      }

      table ip nat {
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          ${optionalString cfg.enableIpv4Masquerade ''
            oifname ${maybeSet wanInterfaces} masquerade
          ''}
          ${optionalString (cfg.hairpinNat.enable && trustedInterfaces != [ ] && effectiveHairpinCidrs != [ ]) ''
            iifname ${maybeSet trustedInterfaces} oifname ${maybeSet trustedInterfaces} ip daddr { ${cidrSet effectiveHairpinCidrs} } masquerade
          ''}
        }
      }
    '';

    systemd.services.router-firewall-flowtable = mkIf cfg.flowtable.enable {
      description = "Configure nftables flowtable after interfaces are up";
      after = [ "network-online.target" "nftables.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        let
          flowIfaces = if cfg.flowtable.interfaces != [ ] then cfg.flowtable.interfaces else allRouterInterfaces;
        in
        ''
          ${pkgs.nftables}/bin/nft 'add flowtable inet filter f { hook ingress priority 0; devices = { ${quotedSet flowIfaces} }; }' 2>/dev/null || true
          ${pkgs.nftables}/bin/nft 'insert rule inet filter forward position 0 ip protocol { tcp, udp } flow add @f' 2>/dev/null || true
        '';
    };
  };
}
