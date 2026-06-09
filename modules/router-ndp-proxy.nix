{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-ndp-proxy;
  hasRouterHa =
    hasAttrByPath [ "services" "router-ha" "enable" ] options;
  routerHaEnabled =
    hasRouterHa
    && (config.services.router-ha.enable or false);

  prefixSubmodule = types.submodule {
    options = {
      prefix = mkOption {
        type = types.str;
        example = "2001:db8:100::/64";
        description = "IPv6 prefix or address rule proxied through ndppd.";
      };

      method = mkOption {
        type = types.enum [
          "auto"
          "static"
          "interface"
        ];
        default = "auto";
        description = ''
          How ndppd should resolve this prefix. `auto` follows the kernel IPv6
          route table, `static` answers immediately, and `interface` forwards
          solicitations through one declared downstream interface.
        '';
      };

      downstreamInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "br-lan";
        description = ''
          Downstream interface used when `method = "interface"`. Must be one of
          `services.router-ndp-proxy.downstreamInterfaces`.
        '';
      };
    };
  };

  renderRuleMethod =
    rule:
    if rule.method == "auto" then
      "auto"
    else if rule.method == "static" then
      "static"
    else
      "iface ${rule.downstreamInterface}";

  ndppdConfig = ''
    route-ttl ${toString cfg.routeTtlMs}

    proxy ${cfg.upstreamInterface} {
      router ${if cfg.routerAdvertisements then "yes" else "no"}
      timeout ${toString cfg.proxyTimeoutMs}
      ttl ${toString cfg.cacheTtlMs}
    ${concatStringsSep "\n" (map (rule: ''

      rule ${rule.prefix} {
        ${renderRuleMethod rule}
      }
    '') cfg.prefixes)}
    }
  '';

  autoStart = !cfg.ha.singleActiveOwner;
in
{
  options.services.router-ndp-proxy = {
    enable = mkEnableOption "advanced opt-in NDP proxying via ndppd";

    upstreamInterface = mkOption {
      type = types.str;
      example = "eth0";
      description = ''
        Upstream interface on which ndppd listens for Neighbor Solicitation
        traffic.
      '';
    };

    downstreamInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "br-lan"
        "vlan10"
      ];
      description = ''
        Downstream interfaces that serve proxied IPv6 addresses behind the
        router. This keeps the first-slice topology explicit even when a prefix
        rule uses `auto` route lookup.
      '';
    };

    prefixes = mkOption {
      type = types.listOf prefixSubmodule;
      default = [ ];
      example = [
        {
          prefix = "2001:db8:100::/64";
          method = "interface";
          downstreamInterface = "br-lan";
        }
      ];
      description = ''
        Bounded list of proxied IPv6 rules rendered into `ndppd.conf`.
      '';
    };

    routeTtlMs = mkOption {
      type = types.ints.positive;
      default = 30000;
      description = "How often ndppd reloads the kernel IPv6 route table, in milliseconds.";
    };

    proxyTimeoutMs = mkOption {
      type = types.ints.positive;
      default = 500;
      description = "How long ndppd waits for a neighbor advertisement before invalidating an entry, in milliseconds.";
    };

    cacheTtlMs = mkOption {
      type = types.ints.positive;
      default = 30000;
      description = "How long valid or invalid proxy cache entries remain, in milliseconds.";
    };

    routerAdvertisements = mkOption {
      type = types.bool;
      default = true;
      description = "Whether ndppd should set the router flag in Neighbor Advertisement replies.";
    };

    ha = {
      singleActiveOwner = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable promotion-aware ndppd ownership for HA deployments.

          When true, the router-ndp-proxy service is not started by default.
          `services.router-ha` becomes responsible for starting ndppd on the
          active node and stopping it on backup or fault transitions.

          Requires `services.router-ha.enable = true`.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.upstreamInterface != "";
        message = "services.router-ndp-proxy.upstreamInterface must not be empty.";
      }
      {
        assertion = cfg.downstreamInterfaces != [ ];
        message = ''
          services.router-ndp-proxy requires at least one declared
          downstreamInterfaces entry.
        '';
      }
      {
        assertion = allUnique cfg.downstreamInterfaces;
        message = "services.router-ndp-proxy.downstreamInterfaces must be unique.";
      }
      {
        assertion = cfg.prefixes != [ ];
        message = "services.router-ndp-proxy requires at least one proxied prefix rule.";
      }
      {
        assertion = all (rule: rule.method != "interface" || rule.downstreamInterface != null) cfg.prefixes;
        message = ''
          services.router-ndp-proxy prefix rules using method = "interface"
          must set downstreamInterface.
        '';
      }
      {
        assertion = all (rule: rule.method == "interface" || rule.downstreamInterface == null) cfg.prefixes;
        message = ''
          services.router-ndp-proxy.downstreamInterface is only valid when
          a prefix rule uses method = "interface".
        '';
      }
      {
        assertion =
          all (
            rule:
            rule.downstreamInterface == null
            || elem rule.downstreamInterface cfg.downstreamInterfaces
          ) cfg.prefixes;
        message = ''
          services.router-ndp-proxy prefix rules may only reference declared
          downstreamInterfaces.
        '';
      }
      {
        assertion = !routerHaEnabled || cfg.ha.singleActiveOwner;
        message = ''
          services.router-ndp-proxy with services.router-ha requires explicit
          promotion-aware ownership. Set:
            services.router-ndp-proxy.ha.singleActiveOwner = true;
          This ensures ndppd only runs on the active HA node.
        '';
      }
      {
        assertion = cfg.ha.singleActiveOwner -> routerHaEnabled;
        message = ''
          services.router-ndp-proxy.ha.singleActiveOwner requires
          services.router-ha.enable = true.
        '';
      }
    ];

    environment.etc."ndppd.conf".text = ndppdConfig;

    systemd.services.router-ndp-proxy = {
      description = "Router NDP proxy (ndppd)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = optionals autoStart [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ndppd}/bin/ndppd";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
