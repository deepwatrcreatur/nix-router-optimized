{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-clat;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  routerFirewallEnabled = hasRouterFirewall && attrByPath [ "services" "router-firewall" "enable" ] false config;
  hasRouterNat64 = hasAttrByPath [ "services" "router-nat64" "enable" ] options;
  nat64Enabled = hasRouterNat64 && attrByPath [ "services" "router-nat64" "enable" ] false config;
  nat64Cfg = attrByPath [ "services" "router-nat64" ] { } config;

  # Powers of 2 lookup (0..32) — avoids needing builtins.pow which doesn't exist.
  pow2 = builtins.genList (n: builtins.foldl' (acc: _: acc * 2) 1 (builtins.genList (x: x) n)) 33;

  # Parse an IPv4 CIDR "a.b.c.d/n" into { start; end; } as integers.
  parseIpv4Cidr = cidr:
    let
      parts = splitString "/" cidr;
      octets = map toInt (splitString "." (head parts));
      prefixLen = toInt (last parts);
      addr = builtins.foldl' (acc: o: acc * 256 + o) 0 octets;
      size = elemAt pow2 (32 - prefixLen);
      # Mask to network boundary: integer division then multiply back
      network = (addr / size) * size;
    in { start = network; end = network + size - 1; };

  # Check if two IPv4 CIDRs overlap (share any addresses).
  ipv4CidrsOverlap = a: b:
    let
      ra = parseIpv4Cidr a;
      rb = parseIpv4Cidr b;
    in ra.start <= rb.end && rb.start <= ra.end;

  # For IPv6 prefixes, full overlap math on 128-bit values is impractical in
  # pure Nix.  Both router-clat and router-nat64 use /96 prefixes, so we
  # compare the prefix portion (everything before the /96) for containment.
  # If either prefix is shorter than /96, we fall back to string inequality
  # as a conservative guard.
  ipv6PrefixesOverlap = a: b:
    let
      aPrefix = head (splitString "/" a);
      bPrefix = head (splitString "/" b);
      aLen = toInt (last (splitString "/" a));
      bLen = toInt (last (splitString "/" b));
    in
      if aLen == 96 && bLen == 96 then aPrefix == bPrefix
      else a == b;  # conservative fallback

  # Parse CIDR helpers for config generation
  cidrAddress = cidr: head (splitString "/" cidr);
  cidrPrefixLen = cidr: toInt (last (splitString "/" cidr));

  # First address in pool is used as the Tayga router address on that side
  ipv4RouterAddr = cidrAddress cfg.legacyIpv4Pool;
  ipv6RouterAddr = "${cidrAddress cfg.mappingPrefix6}1";

  # Python control-plane daemon with its dependencies
  clatDnsPython = pkgs.python3.withPackages (_ps: []);
  clatDnsScript = ./router-clat/clat-dns.py;

  # Build upstream resolver CLI args
  upstreamArgs = concatMapStringsSep " " (r: "--upstream ${r}") cfg.upstreamResolvers;

  # Tayga config for the CLAT instance
  taygaConf = pkgs.writeText "router-clat-tayga.conf" ''
    tun-device clat0
    ipv4-addr ${ipv4RouterAddr}
    ipv6-addr ${ipv6RouterAddr}
    prefix ${cfg.mappingPrefix6}
    dynamic-pool ${cfg.legacyIpv4Pool}
    data-dir /var/lib/router-clat
  '';
in
{
  options.services.router-clat = {
    enable = mkEnableOption "experimental CLAT-style IPv4-to-IPv6 translation";

    upstreamInterface = mkOption {
      type = types.str;
      description = "WAN interface with working IPv6 connectivity.";
    };

    listenInterfaces = mkOption {
      type = types.listOf types.str;
      description = "LAN interfaces where legacy IPv4 clients live.";
    };

    legacyIpv4Pool = mkOption {
      type = types.str;
      default = "100.64.46.0/24";
      description = "Private IPv4 CIDR for synthetic address allocation.";
    };

    mappingPrefix6 = mkOption {
      type = types.str;
      default = "fd46:ca17:1::/96";
      description = "IPv6 /96 prefix for translated address construction.";
    };

    mappingTtl = mkOption {
      type = types.int;
      default = 1800;
      description = "Mapping lifetime in seconds since last use (default: 30 min).";
    };

    gcInterval = mkOption {
      type = types.int;
      default = 60;
      description = "Seconds between garbage collection sweeps.";
    };

    upstreamResolvers = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "DNS resolvers the CLAT listener queries upstream.";
    };

    dnsListenPort = mkOption {
      type = types.int;
      default = 53;
      description = "Port for the CLAT DNS listener on listenInterfaces.";
    };

    preferSynthesizedAnswers = mkOption {
      type = types.bool;
      default = false;
      description = "Prefer synthesized A over native A for dual-stack upstream answers.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Inject router-firewall rules for CLAT traffic when router-firewall is enabled.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.listenInterfaces != [];
          message = "router-clat: listenInterfaces must not be empty.";
        }
        {
          assertion = !(elem cfg.upstreamInterface cfg.listenInterfaces);
          message = "router-clat: upstreamInterface (${cfg.upstreamInterface}) must not appear in listenInterfaces — this would create a routing loop.";
        }
        {
          assertion = cfg.mappingTtl > cfg.gcInterval;
          message = "router-clat: mappingTtl (${toString cfg.mappingTtl}s) must be greater than gcInterval (${toString cfg.gcInterval}s).";
        }
        {
          assertion = !nat64Enabled || !ipv4CidrsOverlap cfg.legacyIpv4Pool (nat64Cfg.ipv4Pool or "0.0.0.0/32");
          message = "router-clat: legacyIpv4Pool (${cfg.legacyIpv4Pool}) must not overlap router-nat64.ipv4Pool (${nat64Cfg.ipv4Pool or "?"}).";
        }
        {
          assertion = !nat64Enabled || !ipv6PrefixesOverlap cfg.mappingPrefix6 (nat64Cfg.ipv6Prefix or "::/128");
          message = "router-clat: mappingPrefix6 (${cfg.mappingPrefix6}) must not overlap router-nat64.ipv6Prefix (${nat64Cfg.ipv6Prefix or "?"}).";
        }
      ];

      warnings = [
        "router-clat: this is an experimental first-slice module. It currently validates contract and topology assumptions, but does not yet claim a complete router-grade runtime translation implementation."
        "router-clat: the current slice should be treated as single-router and non-HA. Active-owner/failover behavior remains intentionally narrow."
        "router-clat: the `router-clat` name remains provisional until the runtime story and operator-facing boundary stabilize."
      ] ++ optional (hasRouterFirewall && !routerFirewallEnabled)
        "router-clat: router-firewall is not enabled. Defense-in-depth recommends enabling router-firewall when using CLAT translation.";

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = mkDefault 1;
        "net.ipv6.conf.all.forwarding" = mkDefault 1;
      };
    }

    # Firewall integration
    (optionalAttrs hasRouterFirewall (mkIf (cfg.openFirewall && routerFirewallEnabled) {
      services.router-firewall.extraInputRules = ''
        iifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} tcp dport ${toString cfg.dnsListenPort} accept comment "CLAT DNS listener"
        iifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} udp dport ${toString cfg.dnsListenPort} accept comment "CLAT DNS listener"
      '';

      services.router-firewall.extraForwardRules = ''
        iifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} oifname "clat0" accept comment "CLAT: LAN to translation"
        iifname "clat0" oifname "${cfg.upstreamInterface}" accept comment "CLAT: translation to WAN"
        iifname "${cfg.upstreamInterface}" oifname "clat0" accept comment "CLAT: WAN to translation (return)"
        iifname "clat0" oifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} accept comment "CLAT: translation to LAN (return)"
      '';
    }))

    # Runtime backend: Tayga instance + clat0 interface lifecycle
    {
      # Tayga config artifact — inspectable at /etc/router-clat/tayga.conf
      environment.etc."router-clat/tayga.conf".source = taygaConf;

      # clat0 TUN interface owned by systemd-networkd
      systemd.network.netdevs."30-clat0" = {
        netdevConfig = {
          Name = "clat0";
          Kind = "tun";
        };
      };

      systemd.network.networks."30-clat0" = {
        matchConfig.Name = "clat0";
        addresses = [
          { Address = "${ipv4RouterAddr}/32"; }
          { Address = "${ipv6RouterAddr}/128"; }
        ];
        routes = [
          {
            Destination = cfg.legacyIpv4Pool;
          }
          {
            Destination = cfg.mappingPrefix6;
          }
        ];
        linkConfig.RequiredForOnline = "no";
      };

      # DNS synthesis and mapping control plane
      systemd.services.router-clat-dns = {
        description = "CLAT DNS synthesis and mapping control plane";
        after = [
          "network-online.target"
          "router-clat-tayga.service"
        ];
        wants = [ "network-online.target" ];
        requires = [ "router-clat-tayga.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = concatStringsSep " " ([
            "${clatDnsPython}/bin/python3"
            "${clatDnsScript}"
            "--pool ${cfg.legacyIpv4Pool}"
            "--mapping-ttl ${toString cfg.mappingTtl}"
            "--gc-interval ${toString cfg.gcInterval}"
            "--state-dir /var/lib/router-clat"
            "--artifact-path /run/router-clat/mappings.json"
            upstreamArgs
          ]
          ++ [ "--listen 0.0.0.0" ]
          ++ [ "--port ${toString cfg.dnsListenPort}" ]
          ++ optional cfg.preferSynthesizedAnswers "--prefer-synthesized"
          ++ [ "--reload-cmd" "'${pkgs.systemd}/bin/systemctl reload router-clat-tayga.service'" ]);

          Restart = "on-failure";
          RestartSec = 5;

          StateDirectory = "router-clat";
          RuntimeDirectory = "router-clat";

          # Hardening
          ProtectHome = true;
          ProtectSystem = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectHostname = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          NoNewPrivileges = true;
          LockPersonality = true;
          PrivateTmp = true;
          SystemCallArchitectures = "native";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      # Tayga translation daemon — separate instance from router-nat64
      systemd.services.router-clat-tayga = {
        description = "CLAT translation backend (Tayga)";
        after = [
          "network-online.target"
          "systemd-networkd.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        reloadTriggers = [ taygaConf ];

        serviceConfig = {
          ExecStart = "${pkgs.tayga}/bin/tayga -d --nodetach --config /etc/router-clat/tayga.conf";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGHUP $MAINPID";
          Restart = "on-failure";
          RestartSec = 5;

          StateDirectory = "router-clat";

          # Hardening
          ProtectHome = true;
          ProtectSystem = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectHostname = true;
          ProtectControlGroups = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          NoNewPrivileges = true;
          LockPersonality = true;
          PrivateTmp = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@network-io"
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          AmbientCapabilities = [ "CAP_NET_ADMIN" ];
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
        };
      };
    }
  ]);
}
