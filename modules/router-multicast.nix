{
  config,
  options,
  lib,
  pkgs,
  ...
}:

# IPv4 multicast proxying (IGMP proxy) for IPTV and similar streams, using
# igmpproxy. See docs/router-multicast.md.
with lib;

let
  cfg = config.services.router-multicast;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  firewallEnabled = hasRouterFirewall && (config.services.router-firewall.enable or false);
  quote = d: ''"${d}"'';
  nftSet = ds: "{ ${concatMapStringsSep ", " quote ds} }";

  filterLines =
    lists:
    concatMapStrings (n: "  whitelist ${n}\n") lists.allowGroups
    + concatMapStrings (n: "  blacklist ${n}\n") lists.denyGroups;

  configFile = pkgs.writeText "igmpproxy.conf" (
    optionalString cfg.quickLeave "quickleave\n"
    + ''
      phyint ${cfg.upstream.interface} upstream ratelimit 0 threshold 1
    ''
    + concatMapStrings (n: "  altnet ${n}\n") cfg.upstream.sources
    + filterLines cfg.upstream
    + concatMapStrings (
      d:
      ''
        phyint ${d} downstream ratelimit 0 threshold 1
      ''
      + filterLines cfg
    ) cfg.downstreams
    # INVARIANT: other interfaces are not listed; igmpproxy 0.4 leaves
    # unlisted interfaces disabled unless `defaultdown` is set, which this
    # module never writes (vm-router-multicast checks a second VLAN).
  );

  groupList =
    description:
    mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "239.0.0.0/8" ];
      inherit description;
    };
in
{
  options.services.router-multicast = {
    enable = mkEnableOption "IPv4 multicast proxying (IGMP proxy) with igmpproxy";

    upstream = {
      interface = mkOption {
        type = types.str;
        example = "wan0.40";
        description = ''
          Interface facing the multicast source, often an ISP IPTV VLAN. Not
          assumed to be the WAN.
        '';
      };

      sources = mkOption {
        type = types.listOf types.str;
        default = [ "0.0.0.0/0" ];
        example = [ "10.0.0.0/8" ];
        description = ''
          Networks multicast may come from (igmpproxy `altnet`). igmpproxy
          otherwise only accepts sources on the upstream interface's own
          subnet, and IPTV sources are usually remote.
        '';
      };

      allowGroups = groupList "Groups that may be joined upstream (igmpproxy `whitelist`); empty allows all.";
      denyGroups = groupList "Groups never joined upstream (igmpproxy `blacklist`).";
    };

    downstreams = mkOption {
      type = types.listOf types.str;
      example = [ "lan0" ];
      description = ''
        Interfaces whose receivers may join groups. Only these get the
        streams; every other interface stays disabled for multicast routing
        and the firewall forwards 224.0.0.0/4 only to these.
      '';
    };

    allowGroups = groupList "Groups receivers may join on the downstreams (igmpproxy `whitelist`); empty allows all.";
    denyGroups = groupList "Groups receivers may not join on the downstreams (igmpproxy `blacklist`).";

    quickLeave = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Leave a group upstream as soon as the last receiver on any downstream
        leaves, instead of waiting for membership to time out. Faster
        channel changes and less upstream bandwidth; with several receivers
        of one group on a downstream, the others can see a short gap while
        igmpproxy re-queries.
      '';
    };

    looseReversePathFilter = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Set the upstream interface's `rp_filter` to 2 (loose) when igmpproxy
        starts. Strict mode drops multicast from sources that are not routed
        back via the upstream, which is the usual IPTV case. The kernel
        applies the larger of `all` and the interface value, so loose mode
        also overrides a strict `all` (router-security-hardened).
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.downstreams != [ ];
          message = "services.router-multicast.downstreams must list at least one interface.";
        }
        {
          assertion = !(elem cfg.upstream.interface cfg.downstreams);
          message = "services.router-multicast: ${cfg.upstream.interface} cannot be both upstream and downstream.";
        }
        {
          assertion = allUnique cfg.downstreams;
          message = "services.router-multicast.downstreams must be unique.";
        }
      ];

      systemd.services.router-multicast = {
        description = "IGMP proxy for multicast streams (igmpproxy)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStartPre = optional cfg.looseReversePathFilter "+${pkgs.writeShellScript "router-multicast-rp-filter" ''
            ${pkgs.coreutils}/bin/echo 2 > ${escapeShellArg "/proc/sys/net/ipv4/conf/${cfg.upstream.interface}/rp_filter"}
          ''}";
          ExecStart = "${pkgs.igmpproxy}/bin/igmpproxy -n ${configFile}";
          Restart = "on-failure";
          RestartSec = "5s";
          # igmpproxy needs raw sockets and the multicast routing API.
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          DynamicUser = false;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };
    }

    (optionalAttrs hasRouterFirewall {
      # WHY: early hooks run before the per-zone jumps; WAN_LOCAL and WAN_IN
      # end in drop, and the upstream is often a WAN-zone VLAN.
      services.router-firewall.extraInputEarlyRules = mkIf firewallEnabled ''
        iifname ${nftSet ([ cfg.upstream.interface ] ++ cfg.downstreams)} ip protocol igmp accept comment "IGMP proxy"
      '';
      # GOTCHA: only the listed downstreams get group traffic; other
      # segments fall through to the forward chain's drop policy.
      services.router-firewall.extraForwardEarlyRules = mkIf firewallEnabled ''
        iifname ${quote cfg.upstream.interface} oifname ${nftSet cfg.downstreams} ip daddr 224.0.0.0/4 accept comment "IGMP proxy streams"
      '';
    })
  ]);
}
