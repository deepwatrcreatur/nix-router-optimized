{
  config,
  lib,
  modulesPath,
  ...
}:

with lib;

let
  cfg = config.services.router-cloudflare-tunnel;

  ingressRuleModule = types.submodule ({ ... }: {
    options = {
      service = mkOption {
        type = types.str;
        description = "Origin service URL for this ingress rule, for example http://127.0.0.1:3000.";
      };

      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional path filter for this ingress rule.";
      };
    };
  });

  mkIngress = ingress:
    mapAttrs (
      _: rule:
      if builtins.isString rule then
        rule
      else
        {
          service = rule.service;
        }
        // optionalAttrs (rule.path != null) { inherit (rule) path; }
    ) ingress;

  derivedPublicUrl =
    tunnel:
    if tunnel.publicUrl != null then
      tunnel.publicUrl
    else
      let
        hostnames = attrNames tunnel.ingress;
      in
      if length hostnames == 1 then "https://${head hostnames}" else null;
in
{
  imports = [
    "${modulesPath}/services/networking/cloudflared.nix"
    ./router-tunnels.nix
  ];

  options.services.router-cloudflare-tunnel = {
    enable = mkEnableOption "router-oriented Cloudflare Tunnel management via cloudflared";

    certificateFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional Cloudflare account certificate used by `cloudflared` when
        needed for declarative tunnel management. This is forwarded to
        `services.cloudflared.certificateFile`.
      '';
    };

    tunnels = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              credentialsFile = mkOption {
                type = types.path;
                description = "Path to the Cloudflare tunnel credentials JSON file.";
              };

              certificateFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Optional per-tunnel account certificate file.";
              };

              description = mkOption {
                type = types.str;
                default = "";
                description = "Human-readable description surfaced in the dashboard.";
              };

              publicUrl = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Optional canonical public URL for dashboard display. If omitted
                  and exactly one ingress hostname is configured, the module
                  derives `https://<hostname>`.
                '';
              };

              default = mkOption {
                type = types.str;
                default = "http_status:404";
                description = "Catch-all service when no ingress hostname matches.";
              };

              edgeIPVersion = mkOption {
                type = types.enum [
                  "auto"
                  "4"
                  "6"
                ];
                default = "4";
                description = "IP family preference for the edge connection.";
              };

              warpRouting.enable = mkOption {
                type = types.bool;
                default = false;
                description = "Enable WARP routing for this tunnel.";
              };

              ingress = mkOption {
                type = types.attrsOf (types.either types.str ingressRuleModule);
                default = { };
                description = ''
                  Hostname-to-service mapping for Cloudflare ingress. Each value
                  can be a raw service string or an attrset with `service` and
                  optional `path`.
                '';
                example = {
                  "grafana.example.com" = "http://127.0.0.1:3001";
                  "ssh.example.com" = {
                    service = "ssh://127.0.0.1:22";
                  };
                };
              };
            };
          }
        )
      );
      default = { };
      description = "Named Cloudflare tunnels managed by cloudflared.";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      [
        {
          assertion = cfg.tunnels != { };
          message = "services.router-cloudflare-tunnel.tunnels must define at least one tunnel.";
        }
      ]
      ++ mapAttrsToList (
        name: tunnel:
        {
          assertion = tunnel.ingress != { };
          message = "services.router-cloudflare-tunnel.tunnels.${name}.ingress must define at least one hostname.";
        }
      ) cfg.tunnels;

    services.cloudflared =
      {
        enable = true;
        tunnels = mapAttrs (
          _: tunnel:
          {
            inherit (tunnel)
              credentialsFile
              default
              edgeIPVersion
              ;
            ingress = mkIngress tunnel.ingress;
          }
          // optionalAttrs (tunnel.certificateFile != null) { certificateFile = tunnel.certificateFile; }
          // optionalAttrs tunnel.warpRouting.enable {
            "warp-routing".enabled = true;
          }
        ) cfg.tunnels;
      }
      // optionalAttrs (cfg.certificateFile != null) { inherit (cfg) certificateFile; };

    services.router-tunnels = {
      enable = true;
      tunnels = mkAfter (
        mapAttrsToList (name: tunnel: {
          inherit (tunnel) description;
          name = name;
          provider = "cloudflare";
          unit = "cloudflared-tunnel-${name}";
          publicUrl = derivedPublicUrl tunnel;
        }) cfg.tunnels
      );
    };
  };
}
