{
  services.router-dashboard.enable = true;

  services.router-tunnels = {
    enable = true;
    tunnels = [
      {
        name = "grafana-share";
        provider = "cloudflare";
        systemdUnit = "cloudflared-grafana.service";
        publicUrl = "https://grafana.example.com";
        description = "Cloudflare Tunnel for external Grafana access";
      }
      {
        name = "support-zrok";
        provider = "zrok";
        systemdUnit = "zrok-share-support.service";
        description = "Ephemeral support tunnel";
      }
    ];
  };

  services.router-remote-admin = {
    enable = true;
    entries = [
      {
        name = "guac";
        kind = "guacamole";
        systemdUnit = "guacd.service";
        url = "https://guac.example.com";
        description = "Browser-based remote desktop gateway";
      }
      {
        name = "bastion";
        kind = "ssh";
        systemdUnit = "sshd.service";
        url = "ssh://router.example.com";
        description = "Primary SSH bastion";
      }
    ];
  };
}
