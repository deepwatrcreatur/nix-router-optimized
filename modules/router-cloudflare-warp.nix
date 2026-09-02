{
  config,
  options,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-cloudflare-warp;
  hasRouterFirewallOption = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  ageSecrets = config.age.secrets or { };
  hasLicenseSecret = cfg.licenseKeySecretName != null && hasAttr cfg.licenseKeySecretName ageSecrets;
  licenseKeyPath = if hasLicenseSecret then config.age.secrets.${cfg.licenseKeySecretName}.path else null;
in
{
  options.services.router-cloudflare-warp = {
    enable = mkEnableOption "Cloudflare WARP outbound VPN tunnel for download acceleration and privacy";

    mode = mkOption {
      type = types.enum [ "warp" "doh" "warp+doh" ];
      default = "warp";
      description = "Operating mode for Cloudflare WARP daemon.";
    };

    licenseKeySecretName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional Age secret name containing a Cloudflare WARP+ license key for higher speeds.";
    };

    routingMode = mkOption {
      type = types.enum [ "all-traffic" "selective-lan-ips" ];
      default = "selective-lan-ips";
      description = ''
        Outbound routing policy for WARP traffic.
        'all-traffic': routes default WAN traffic through WARP.
        'selective-lan-ips': routes specific targetLanIps through WARP via nftables policy routing.
      '';
    };

    targetLanIps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.11.73" "10.10.11.84" ];
      description = "LAN client IP addresses to route through Cloudflare WARP when routingMode = 'selective-lan-ips'.";
    };

    interfaceName = mkOption {
      type = types.str;
      default = "warp0";
      description = "Network interface created by Cloudflare WARP.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.cloudflare-warp = {
        enable = true;
        package = pkgs.cloudflare-warp;
      };

      systemd.services.router-cloudflare-warp-setup = {
        description = "Configure Cloudflare WARP connection and license";
        after = [ "cloudflare-warp.service" "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          WARP_CLI="${pkgs.cloudflare-warp}/bin/warp-cli"

          for i in {1..15}; do
            if $WARP_CLI status >/dev/null 2>&1; then
              break
            fi
            sleep 1
          done

          # Register if not already registered
          if ! $WARP_CLI status | grep -i "Registration" >/dev/null 2>&1; then
            $WARP_CLI registration new || true
          fi

          ${optionalString (licenseKeyPath != null) ''
            if [ -f "${licenseKeyPath}" ]; then
              LICENSE="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${licenseKeyPath}")"
              if [ -n "$LICENSE" ]; then
                $WARP_CLI registration license "$LICENSE" || true
              fi
            fi
          ''}

          $WARP_CLI mode ${cfg.mode} || true
          $WARP_CLI connect || true
        '';
      };
    }
    (
      if hasRouterFirewallOption then
        {
          services.router-firewall = mkIf (config.services.router-firewall.enable or false) {
            trustedInterfaces = [ cfg.interfaceName ];
          };
        }
      else
        { }
    )
  ]);
}
