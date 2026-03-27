{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-firewall;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };

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

  quotedSet = ifaces: concatStringsSep ", " (map (iface: "\"${iface}\"") ifaces);
  maybeSet = ifaces: if ifaces == [ ] then "" else "{${quotedSet ifaces}}";
  tcpPortSet = ports: concatStringsSep ", " (map toString ports);

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

    flowtable.enable = mkEnableOption "nftables flowtable acceleration" // {
      default = true;
    };

    flowtable.interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Interfaces used by the nftables flowtable. Defaults to all router interfaces.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.autoInterfacesFromOptimizations || wanInterfaces != [ ];
        message = "router-firewall needs at least one WAN interface, either explicit or derived from router-optimizations.";
      }
    ];

    networking.nftables.enable = true;
    networking.firewall.enable = false;

    networking.nftables.ruleset = ''
      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;

          ct state {established, related} accept
          iifname "lo" accept

          ip protocol icmp accept
          ${optionalString cfg.enableIpv6 "ip6 nexthdr icmpv6 accept"}

          ${optionalString (cfg.enableIpv6 && wanInterfaces != [ ]) ''
            iifname ${maybeSet wanInterfaces} udp dport 546 accept
          ''}

          ${optionalString (cfg.allowSsh && trustedInterfaces != [ ]) ''
            iifname ${maybeSet trustedInterfaces} tcp dport 22 accept
          ''}

          ${
            let dnsIfaces = if cfg.dnsInterfaces != [ ] then cfg.dnsInterfaces else trustedInterfaces;
            in optionalString (dnsIfaces != [ ] && cfg.dnsUdpPorts != [ ]) ''
              iifname ${maybeSet dnsIfaces} udp dport {${tcpPortSet cfg.dnsUdpPorts}} accept
            '' + optionalString (dnsIfaces != [ ] && elem 67 cfg.dnsUdpPorts && elem 68 cfg.dnsUdpPorts) ''
              iifname ${maybeSet dnsIfaces} udp sport {67, 68} accept
            '' + optionalString (dnsIfaces != [ ] && cfg.dnsTcpPorts != [ ]) ''
              iifname ${maybeSet dnsIfaces} tcp dport {${tcpPortSet cfg.dnsTcpPorts}} accept
            ''
          }

          ${optionalString (trustedInterfaces != [ ] && cfg.trustedTcpPorts != [ ]) ''
            iifname ${maybeSet trustedInterfaces} tcp dport {${tcpPortSet cfg.trustedTcpPorts}} accept
          ''}
          ${optionalString (trustedInterfaces != [ ] && cfg.trustedUdpPorts != [ ]) ''
            iifname ${maybeSet trustedInterfaces} udp dport {${tcpPortSet cfg.trustedUdpPorts}} accept
          ''}

          ${optionalString (wanInterfaces != [ ] && cfg.wanTcpPorts != [ ]) ''
            iifname ${maybeSet wanInterfaces} tcp dport {${tcpPortSet cfg.wanTcpPorts}} accept
          ''}
          ${optionalString (wanInterfaces != [ ] && cfg.wanUdpPorts != [ ]) ''
            iifname ${maybeSet wanInterfaces} udp dport {${tcpPortSet cfg.wanUdpPorts}} accept
          ''}

          ${optionalString (cfg.tailscaleInterface != null) ''
            iifname "${cfg.tailscaleInterface}" accept
          ''}

          ${cfg.extraInputRules}

          log prefix "${cfg.inputLogPrefix}" level info flags all
          drop
        }

        chain forward {
          type filter hook forward priority 0; policy drop;

          ct state {established, related} accept
          ct state invalid log prefix "${cfg.invalidLogPrefix}" level info flags all
          ct state invalid drop

          ${optionalString cfg.lanToWan (mkForwardRule lanInterfaces wanInterfaces "accept")}
          ${optionalString cfg.managementToWan (mkForwardRule managementInterfaces wanInterfaces "accept")}

          ${
            if cfg.allowTrustedInterconnect && trustedInterfaces != [ ] then
              ''
                iifname ${maybeSet trustedInterfaces} oifname ${maybeSet trustedInterfaces} accept
              ''
            else
              ""
          }

          ${optionalString (cfg.tailscaleInterface != null && allRouterInterfaces != [ ]) ''
            iifname "${cfg.tailscaleInterface}" oifname ${maybeSet allRouterInterfaces} accept
            iifname ${maybeSet trustedInterfaces} oifname "${cfg.tailscaleInterface}" accept
          ''}

          ${cfg.extraForwardRules}

          log prefix "${cfg.forwardLogPrefix}" level info flags all
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
