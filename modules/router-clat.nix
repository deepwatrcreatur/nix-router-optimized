{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-clat;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  routerFirewallEnabled = hasRouterFirewall && attrByPath [ "services" "router-firewall" "enable" ] false config;
  hasRouterNat64 = hasAttrByPath [ "services" "router-nat64" "enable" ] options;
  nat64Enabled = hasRouterNat64 && attrByPath [ "services" "router-nat64" "enable" ] false config;
  nat64Cfg = attrByPath [ "services" "router-nat64" ] { } config;
  hasJoolCli = builtins.hasAttr "jool-cli" pkgs;
  joolUnsupportedMessage =
    if hasJoolCli then
      "router-clat: translationBackend.backend = jool-experimental is only a bounded spike today. nixpkgs exposes jool-cli, but this repo does not yet have a supported Jool runtime/kernel-module lifecycle for CLAT."
    else
      "router-clat: translationBackend.backend = jool-experimental is unavailable here because nixpkgs does not expose the required Jool runtime packaging.";

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

  # First address in pool is used as the Tayga router address on that side
  ipv4RouterAddr = cidrAddress cfg.legacyIpv4Pool;
  ipv6RouterAddr = "${cidrAddress cfg.mappingPrefix6}1";

  translationBackendLib = import ./router-translation-backend-lib.nix { inherit lib; };
  translationBackend = translationBackendLib.mkTaygaAdapter {
    interfaceName = "clat0";
    ipv4Pool = cfg.legacyIpv4Pool;
    ipv6Prefix = cfg.mappingPrefix6;
    inherit ipv4RouterAddr ipv6RouterAddr;
    stateDirectory = "/var/lib/router-clat";
    serviceUnit = "router-clat-tayga.service";
  };

  # Python control-plane daemon with its dependencies
  clatDnsPython = pkgs.python3.withPackages (_ps: []);
  clatDnsScript = ./router-clat/clat-dns.py;
  clatDnsElixir = pkgs.elixir;
  clatDnsElixirScript = ./router-clat/clat-dns-elixir.exs;

  # Build upstream resolver CLI args
  upstreamArgs = concatMapStringsSep " " (r: "--upstream ${r}") cfg.upstreamResolvers;

  # Current backend implementation remains Tayga, but NAT64 and CLAT now render
  # through a shared internal adapter surface rather than duplicating strings.
  taygaConf = pkgs.writeText "router-clat-tayga.conf" translationBackend.tayga.configText;
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

    statusPort = mkOption {
      type = types.int;
      default = 9467;
      description = "HTTP port for the CLAT runtime status endpoint (localhost only).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Inject router-firewall rules for CLAT traffic when router-firewall is enabled.";
    };

    controlPlane = {
      backend = mkOption {
        type = types.enum [ "python" "elixir-preview" ];
        default = "python";
        description = "Select the CLAT control-plane implementation path.";
      };

      allowExperimentalElixir = mkOption {
        type = types.bool;
        default = false;
        description = "Require an explicit opt-in before selecting the experimental Elixir preview path.";
      };
    };

    translationBackend = {
      backend = mkOption {
        type = types.enum [ "tayga" "jool-experimental" ];
        default = "tayga";
        description = "Current CLAT translation backend selection. Jool remains experimental and unsupported beyond bounded spike evaluation.";
      };

      allowExperimentalJool = mkOption {
        type = types.bool;
        default = false;
        description = "Require explicit acknowledgement before selecting the bounded Jool evaluation path.";
      };
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
        {
          assertion = cfg.controlPlane.backend != "elixir-preview" || cfg.controlPlane.allowExperimentalElixir;
          message = "router-clat: controlPlane.backend = elixir-preview requires controlPlane.allowExperimentalElixir = true so preview selection cannot happen silently.";
        }
        {
          assertion = cfg.translationBackend.backend != "jool-experimental" || cfg.translationBackend.allowExperimentalJool;
          message = "router-clat: translationBackend.backend = jool-experimental requires translationBackend.allowExperimentalJool = true so experimental backend selection cannot happen silently.";
        }
        {
          assertion = cfg.translationBackend.backend != "jool-experimental";
          message = joolUnsupportedMessage;
        }
        {
          assertion = !nat64Enabled || cfg.translationBackend.backend == (nat64Cfg.translationBackend.backend or "tayga");
          message = "router-clat: when router-nat64 and router-clat are both enabled, they must agree on translationBackend.backend.";
        }
      ];

      warnings = [
        "router-clat: this is an experimental first-slice module. It currently validates contract and topology assumptions, but does not yet claim a complete router-grade runtime translation implementation."
        "router-clat: the current slice should be treated as single-router and non-HA. Active-owner/failover behavior remains intentionally narrow."
        "router-clat: the `router-clat` name remains provisional until the runtime story and operator-facing boundary stabilize."
      ] ++ optional (cfg.controlPlane.backend == "elixir-preview")
        "router-clat: controlPlane.backend = elixir-preview is a non-default parity path. It should be treated as experimental until preservation and operator evidence are stronger."
      ++ [
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
        iifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} oifname "${translationBackend.runtime.interfaceName}" accept comment "CLAT: LAN to translation"
        iifname "${translationBackend.runtime.interfaceName}" oifname "${cfg.upstreamInterface}" accept comment "CLAT: translation to WAN"
        iifname "${cfg.upstreamInterface}" oifname "${translationBackend.runtime.interfaceName}" accept comment "CLAT: WAN to translation (return)"
        iifname "${translationBackend.runtime.interfaceName}" oifname {${concatMapStringsSep ", " (i: "\"${i}\"") cfg.listenInterfaces}} accept comment "CLAT: translation to LAN (return)"
      '';
    }))

    # Runtime backend: Tayga instance + clat0 interface lifecycle
    {
      # Tayga config artifact — inspectable at /etc/router-clat/tayga.conf
      environment.etc."router-clat/tayga.conf".source = taygaConf;

      # Current translation interface is still clat0, but its lifecycle is
      # described through the shared backend adapter surface.
      systemd.network.netdevs."30-${translationBackend.runtime.interfaceName}" = {
        netdevConfig = {
          Name = translationBackend.runtime.interfaceName;
          Kind = "tun";
        };
      };

      systemd.network.networks."30-${translationBackend.runtime.interfaceName}" = {
        matchConfig.Name = translationBackend.runtime.interfaceName;
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
        path = [ pkgs.systemd ];

        serviceConfig = {
          ExecStart = concatStringsSep " " ([
            (if cfg.controlPlane.backend == "python" then "${clatDnsPython}/bin/python3" else "${clatDnsElixir}/bin/elixir")
            (if cfg.controlPlane.backend == "python" then "${clatDnsScript}" else "${clatDnsElixirScript}")
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
          ++ [
            "--status-port ${toString cfg.statusPort}"
            "--status-path /run/router-clat/status.json"
            "--reload-cmd" "'${pkgs.systemd}/bin/systemctl reload ${translationBackend.runtime.serviceUnit}'"
          ]);

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
            "AF_UNIX"
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
