{
  config,
  lib,
  pkgs,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-pangolin;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
in
{
  options.services.router-pangolin = {
    enable = mkEnableOption "router-aware Pangolin tunnel/reverse proxy integration";

    baseDomain = mkOption {
      type = types.nullOr types.str;
      default = "deepwatercreature.com";
      description = "Base domain for Pangolin tunnel endpoints.";
    };

    dashboardDomain = mkOption {
      type = types.nullOr types.str;
      default = "pangolin.deepwatercreature.com";
      description = "Dashboard domain for Pangolin management interface.";
    };

    letsEncryptEmail = mkOption {
      type = types.nullOr types.str;
      default = "deepwatrcreatur@gmail.com";
      description = "Email for ACME Let's Encrypt certificates.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = "/etc/pangolin/pangolin.env";
      description = "Path to environment file containing secrets for Pangolin.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically open required ports in router-firewall / system firewall.";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Additional configuration settings for Pangolin.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.pangolin = {
        enable = true;
        openFirewall = cfg.openFirewall;
        settings = recursiveUpdate {
          server = {
            # Default internal_port 3001 conflicts with Grafana (http_port = 3001)
            internal_port = 3005;
          };
        } cfg.settings;
      }
      // optionalAttrs (cfg.baseDomain != null) { baseDomain = cfg.baseDomain; }
      // optionalAttrs (cfg.dashboardDomain != null) { dashboardDomain = cfg.dashboardDomain; }
      // optionalAttrs (cfg.letsEncryptEmail != null) { letsEncryptEmail = cfg.letsEncryptEmail; }
      // optionalAttrs (cfg.environmentFile != null) { environmentFile = cfg.environmentFile; };

      systemd.services.pangolin = {
        serviceConfig = {
          # Loosen SocketBindDeny so Node process can bind listening TCP ports on localhost
          SocketBindDeny = lib.mkForce [
            "ipv4:udp"
            "ipv6:udp"
          ];
        } // optionalAttrs (cfg.environmentFile != null) {
          EnvironmentFile = lib.mkForce [ "-${cfg.environmentFile}" ];
        };

        preStart = lib.mkBefore ''
          # Ensure secret file exists
          mkdir -p /etc/pangolin
          if [ ! -f /etc/pangolin/pangolin.env ]; then
            echo "SERVER_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)" > /etc/pangolin/pangolin.env
            chmod 600 /etc/pangolin/pangolin.env
            chown pangolin:fossorial /etc/pangolin/pangolin.env 2>/dev/null || true
          fi

          # Fix read-only permissions on .next directory from Nix store cp -rd and ensure skip setup marker
          if [ -d /var/lib/pangolin/.next ]; then
            chmod -R u+rwX /var/lib/pangolin/.next 2>/dev/null || true
            touch /var/lib/pangolin/.next/.nix_skip_setup 2>/dev/null || true
          fi

          # Ensure database JSON references in server/db are linked from dist
          mkdir -p /var/lib/pangolin/server/db
          for json in ${config.services.pangolin.package}/share/pangolin/dist/*.json; do
            if [ -f "$json" ]; then
              ln -sf "$json" /var/lib/pangolin/server/db/$(basename "$json")
            fi
          done
          chown -R pangolin:fossorial /var/lib/pangolin/server 2>/dev/null || true
        '';
      };
    }
    (optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      services.router-firewall = mkIf (firewallEnabled && cfg.openFirewall) {
        wanTcpPorts = [ 80 443 ];
        trustedTcpPorts = [ 3000 3002 ];
      };
    })
  ]);
}
