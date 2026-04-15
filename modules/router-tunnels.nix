{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-tunnels;

  tunnelModule = types.submodule ({ ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Short identifier for the tunnel (e.g., grafana, ssh).";
      };

      provider = mkOption {
        type = types.enum [ "zrok" "ngrok" "cloudflare" "tailscale-funnel" "frp" "inlets" "other" ];
        description = "Tunnel provider backing this entry (zrok, ngrok, Cloudflare Tunnel, etc.).";
      };

      unit = mkOption {
        type = types.str;
        description = "Systemd unit name backing this tunnel (e.g., zrok-share-grafana.service).";
      };

      publicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Known public URL for the tunnel, when static/predictable.";
      };

      description = mkOption {
        type = types.str;
        default = "";
        description = "Human-readable description of the tunnel's purpose or upstream service.";
      };
    };
  });
in
{
  options.services.router-tunnels = {
    enable = mkEnableOption "metadata for application tunnels (zrok/ngrok/other) exposed on the router dashboard";

    tunnels = mkOption {
      type = types.listOf tunnelModule;
      default = [ ];
      description = ''
        Declarative metadata for application tunnels to surface in the router
        dashboard. This module does not manage tunnel processes; it only
        describes existing units for status display.
      '';
      example = [
        {
          name = "grafana";
          provider = "zrok";
          unit = "zrok-share-grafana.service";
          publicUrl = "https://example-public.zrok.io";
          description = "Read-only Grafana dashboard share";
        }
      ];
    };
  };

  config = mkIf cfg.enable { };
}
