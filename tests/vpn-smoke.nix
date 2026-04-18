{
  self,
  lib,
  eval,
}:

let
  firewallWan = {
    services.router-firewall = {
      enable = true;
      wanInterfaces = [ "eth-wan" ];
    };
  };

  assertModule = assertions: { inherit assertions; };
in
{
  router-wireguard-minimal-eval = eval.mkNixosEvalCheck "router-wireguard-minimal" [
    self.nixosModules.router-wireguard
    {
      services.router-wireguard = {
        enable = true;
        privateKeyFile = "/run/secrets/wireguard-private-key";
      };
    }
    (assertModule [
      {
        assertion = true;
        message = "router-wireguard minimal configuration should evaluate.";
      }
    ])
  ];

  router-wireguard-route-to-wan-eval = eval.mkNixosEvalCheck "router-wireguard-route-to-wan" [
    self.nixosModules.router-firewall
    self.nixosModules.router-wireguard
    firewallWan
    {
      services.router-wireguard = {
        enable = true;
        privateKeyFile = "/run/secrets/wireguard-private-key";
        routeToWan = true;
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix ''iifname "wg0"'' config.services.router-firewall.extraForwardRules;
        message = "router-wireguard routeToWan should add a wg0 forward rule.";
      }
      {
        assertion = lib.hasInfix ''oifname { "eth-wan" }'' config.services.router-firewall.extraForwardRules;
        message = "router-wireguard routeToWan should target the configured WAN interface.";
      }
    ])
  ];

  router-wireguard-route-to-wan-no-wan-fails-eval = eval.mkNixosEvalFailureCheck "router-wireguard-route-to-wan-no-wan" [
    self.nixosModules.router-firewall
    self.nixosModules.router-wireguard
    {
      services.router-firewall = {
        enable = true;
        autoInterfacesFromOptimizations = false;
      };
      services.router-wireguard = {
        enable = true;
        privateKeyFile = "/run/secrets/wireguard-private-key";
        routeToWan = true;
      };
    }
  ];

  router-openvpn-single-wan-eval = eval.mkNixosEvalCheck "router-openvpn-single-wan" [
    self.nixosModules.router-firewall
    self.nixosModules.router-openvpn
    firewallWan
    {
      services.router-openvpn.instances.remote = {
        interfaceName = "tun-remote";
        config = ''
          dev tun-remote
          proto udp
        '';
        trustedInterface = true;
        routeToWan = true;
        wanUdpPorts = [ 1194 ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-firewall.extraTrustedInterfaces == [ "tun-remote" ];
        message = "router-openvpn trusted instance should register its interface.";
      }
      {
        assertion = config.services.router-firewall.wanUdpPorts == [ 1194 ];
        message = "router-openvpn WAN UDP port should be exposed through router-firewall.";
      }
      {
        assertion = lib.hasInfix ''iifname "tun-remote"'' config.services.router-firewall.extraForwardRules;
        message = "router-openvpn routeToWan should add an instance forward rule.";
      }
    ])
  ];

  router-openvpn-multiple-instances-eval = eval.mkNixosEvalCheck "router-openvpn-multiple-instances" [
    self.nixosModules.router-firewall
    self.nixosModules.router-openvpn
    firewallWan
    {
      services.router-openvpn.instances = {
        site-a = {
          interfaceName = "tun-a";
          config = "dev tun-a";
          trustedInterface = true;
          wanUdpPorts = [ 1194 ];
        };
        site-b = {
          interfaceName = "tun-b";
          config = "dev tun-b";
          trustedInterface = true;
          wanTcpPorts = [ 443 ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-firewall.extraTrustedInterfaces == [
          "tun-a"
          "tun-b"
        ];
        message = "router-openvpn should register distinct trusted interfaces for multiple instances.";
      }
      {
        assertion = config.services.router-firewall.wanUdpPorts == [ 1194 ];
        message = "router-openvpn should merge WAN UDP ports from instances.";
      }
      {
        assertion = config.services.router-firewall.wanTcpPorts == [ 443 ];
        message = "router-openvpn should merge WAN TCP ports from instances.";
      }
    ])
  ];

  router-tailscale-with-firewall-eval = eval.mkNixosEvalCheck "router-tailscale-with-firewall" [
    self.nixosModules.router-firewall
    self.nixosModules.router-tailscale
    firewallWan
    {
      services.router-tailscale.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-firewall.overlayInterfaces == [ "tailscale0" ];
        message = "router-tailscale should register tailscale0 as an overlay interface.";
      }
      {
        assertion = config.services.router-firewall.wanUdpPorts == [ 41641 ];
        message = "router-tailscale should expose its UDP port through router-firewall.";
      }
    ])
  ];

  router-tailscale-without-firewall-eval = eval.mkNixosEvalCheck "router-tailscale-without-firewall" [
    self.nixosModules.router-tailscale
    {
      services.router-tailscale.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.tailscale.enable;
        message = "router-tailscale should evaluate without router-firewall imported.";
      }
    ])
  ];

  router-dashboard-vpn-metadata-eval = eval.mkNixosEvalCheck "router-dashboard-vpn-metadata" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-wireguard
    self.nixosModules.router-tailscale
    {
      services.router-dashboard.enable = true;
      services.router-wireguard = {
        enable = true;
        interfaceName = "wg-dashboard";
        privateKeyFile = "/run/secrets/wireguard-private-key";
      };
      services.router-tailscale = {
        enable = true;
        interfaceName = "ts-dashboard";
      };
    }
    (
      { config, ... }:
      let
        vpns = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_VPNS;
      in
      assertModule [
        {
          assertion = builtins.any (
            vpn:
            vpn.kind == "wireguard"
            && vpn.name == "wg-dashboard"
            && vpn.unit == "wireguard-wg-dashboard"
            && vpn.interface == "wg-dashboard"
          ) vpns;
          message = "router-dashboard should export router-wireguard VPN metadata.";
        }
        {
          assertion = builtins.any (
            vpn:
            vpn.kind == "tailscale"
            && vpn.unit == "tailscaled"
            && vpn.interface == "ts-dashboard"
          ) vpns;
          message = "router-dashboard should export router-tailscale VPN metadata.";
        }
      ]
    )
  ];

  router-dashboard-tunnels-metadata-eval = eval.mkNixosEvalCheck "router-dashboard-tunnels-metadata" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-tunnels
    {
      services.router-dashboard.enable = true;
      services.router-tunnels = {
        enable = true;
        tunnels = [
          {
            name = "grafana-share";
            provider = "zrok";
            unit = "zrok-share-grafana.service";
            publicUrl = "https://grafana-share.example.zrok.io";
            description = "Read-only Grafana dashboard share";
          }
          {
            name = "guac-ingress";
            provider = "cloudflare";
            unit = "cloudflared-guac.service";
            publicUrl = "https://guac.example.com";
            description = "Cloudflare Tunnel for Guacamole";
          }
        ];
      };
    }
    (
      { config, ... }:
      let
        tunnels = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_TUNNELS;
      in
      assertModule [
        {
          assertion = builtins.length tunnels == 2;
          message = "router-dashboard should export all configured tunnel metadata.";
        }
        {
          assertion = builtins.any (
            tunnel:
            tunnel.provider == "zrok"
            && tunnel.name == "grafana-share"
            && tunnel.unit == "zrok-share-grafana.service"
            && tunnel.publicUrl == "https://grafana-share.example.zrok.io"
          ) tunnels;
          message = "router-dashboard should export router-tunnels zrok metadata.";
        }
        {
          assertion = builtins.any (
            tunnel:
            tunnel.provider == "cloudflare"
            && tunnel.name == "guac-ingress"
            && tunnel.unit == "cloudflared-guac.service"
            && tunnel.publicUrl == "https://guac.example.com"
            && tunnel.description == "Cloudflare Tunnel for Guacamole"
          ) tunnels;
          message = "router-dashboard should export router-tunnels Cloudflare metadata.";
        }
      ]
    )
  ];

  router-dashboard-remote-admin-metadata-eval = eval.mkNixosEvalCheck "router-dashboard-remote-admin-metadata" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-remote-admin
    {
      services.router-dashboard.enable = true;
      services.router-remote-admin = {
        enable = true;
        entries = [
          {
            name = "guac";
            kind = "guacamole";
            unit = "guacd.service";
            url = "https://guac.example.com";
            description = "Guacamole gateway for lab machines";
          }
          {
            name = "bastion";
            kind = "ssh";
            unit = "sshd.service";
            url = "ssh://router.example.com";
            description = "Primary SSH bastion";
          }
        ];
      };
    }
    (
      { config, ... }:
      let
        remoteAdmin =
          builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_REMOTE_ADMIN;
      in
      assertModule [
        {
          assertion = builtins.length remoteAdmin == 2;
          message = "router-dashboard should export all configured remote admin metadata.";
        }
        {
          assertion = builtins.any (
            entry:
            entry.kind == "guacamole"
            && entry.name == "guac"
            && entry.unit == "guacd.service"
            && entry.url == "https://guac.example.com"
          ) remoteAdmin;
          message = "router-dashboard should export Guacamole remote-admin metadata.";
        }
        {
          assertion = builtins.any (
            entry:
            entry.kind == "ssh"
            && entry.name == "bastion"
            && entry.unit == "sshd.service"
            && entry.url == "ssh://router.example.com"
            && entry.description == "Primary SSH bastion"
          ) remoteAdmin;
          message = "router-dashboard should export SSH remote-admin metadata.";
        }
      ]
    )
  ];

  router-cloudflare-tunnel-wrapper-eval = eval.mkNixosEvalCheck "router-cloudflare-tunnel-wrapper" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-cloudflare-tunnel
    {
      services.router-dashboard.enable = true;
      services.router-cloudflare-tunnel = {
        enable = true;
        tunnels.grafana = {
          credentialsFile = "/run/agenix/cloudflared-grafana.json";
          description = "Cloudflare Tunnel for Grafana";
          ingress = {
            "grafana.example.com" = "http://127.0.0.1:3001";
          };
        };
      };
    }
    (
      { config, ... }:
      let
        tunnels = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_TUNNELS;
      in
      assertModule [
        {
          assertion = config.services.cloudflared.enable;
          message = "router-cloudflare-tunnel should enable services.cloudflared.";
        }
        {
          assertion = builtins.hasAttr "grafana" config.services.cloudflared.tunnels;
          message = "router-cloudflare-tunnel should project tunnels into services.cloudflared.tunnels.";
        }
        {
          assertion = builtins.any (
            tunnel:
            tunnel.provider == "cloudflare"
            && tunnel.name == "grafana"
            && tunnel.unit == "cloudflared-tunnel-grafana"
            && tunnel.publicUrl == "https://grafana.example.com"
          ) tunnels;
          message = "router-cloudflare-tunnel should register dashboard metadata for Cloudflare tunnels.";
        }
      ]
    )
  ];

  router-cloudflare-tunnel-wildcard-url-eval = eval.mkNixosEvalCheck "router-cloudflare-tunnel-wildcard-url" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-cloudflare-tunnel
    {
      services.router-dashboard.enable = true;
      services.router-cloudflare-tunnel = {
        enable = true;
        tunnels.wildcard = {
          credentialsFile = "/run/agenix/cloudflared-wildcard.json";
          ingress = {
            "*.example.com" = "http://127.0.0.1:8080";
          };
        };
      };
    }
    (
      { config, ... }:
      let
        tunnels = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_TUNNELS;
      in
      assertModule [
        {
          assertion = builtins.any (
            tunnel:
            tunnel.name == "wildcard"
            && tunnel.provider == "cloudflare"
            && tunnel.publicUrl == null
          ) tunnels;
          message = "router-cloudflare-tunnel should not derive a dashboard URL from wildcard-only ingress.";
        }
      ]
    )
  ];

  router-dashboard-tunnels-disabled-metadata-eval = eval.mkNixosEvalCheck "router-dashboard-tunnels-disabled-metadata" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-tunnels
    {
      services.router-dashboard.enable = true;
      services.router-tunnels = {
        enable = false;
        tunnels = [
          {
            name = "hidden";
            provider = "cloudflare";
            unit = "cloudflared-hidden.service";
            publicUrl = "https://hidden.example.com";
            description = "Should not be exported when router-tunnels is disabled";
          }
        ];
      };
    }
    (
      { config, ... }:
      let
        tunnels = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_TUNNELS;
      in
      assertModule [
        {
          assertion = tunnels == [ ];
          message = "router-dashboard should not export tunnel metadata when router-tunnels is disabled.";
        }
      ]
    )
  ];

  router-dashboard-remote-admin-disabled-metadata-eval = eval.mkNixosEvalCheck "router-dashboard-remote-admin-disabled-metadata" [
    self.nixosModules.router-dashboard
    self.nixosModules.router-remote-admin
    {
      services.router-dashboard.enable = true;
      services.router-remote-admin = {
        enable = false;
        entries = [
          {
            name = "hidden";
            kind = "ssh";
            unit = "sshd.service";
            url = "ssh://hidden.example.com";
            description = "Should not be exported when router-remote-admin is disabled";
          }
        ];
      };
    }
    (
      { config, ... }:
      let
        remoteAdmin =
          builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_REMOTE_ADMIN;
      in
      assertModule [
        {
          assertion = remoteAdmin == [ ];
          message = "router-dashboard should not export remote-admin metadata when router-remote-admin is disabled.";
        }
      ]
    )
  ];

  router-headscale-standalone-eval = eval.mkNixosEvalCheck "router-headscale-standalone" [
    self.nixosModules.router-headscale
    {
      services.router-headscale = {
        enable = true;
        domain = "headscale.example.com";
        openFirewall = false;
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.headscale.enable;
        message = "router-headscale should enable services.headscale.";
      }
      {
        assertion = config.services.headscale.settings.server_url == "https://headscale.example.com";
        message = "router-headscale should derive Headscale server_url from domain.";
      }
      {
        assertion = config.services.headscale.address == "0.0.0.0";
        message = "router-headscale should listen directly when Caddy is not active.";
      }
    ])
  ];

  router-headscale-with-caddy-eval = eval.mkNixosEvalCheck "router-headscale-with-caddy" [
    self.nixosModules.caddy-reverse-proxy
    self.nixosModules.router-headscale
    {
      services.caddy-router = {
        enable = true;
        domain = "example.com";
        email = "admin@example.com";
      };
      services.router-headscale = {
        enable = true;
        domain = "headscale.example.com";
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.headscale.address == "127.0.0.1";
        message = "router-headscale should bind to loopback when Caddy is active.";
      }
      {
        assertion =
          lib.hasInfix "reverse_proxy http://127.0.0.1:8080"
            config.services.caddy.virtualHosts."headscale.example.com".extraConfig;
        message = "router-headscale should add a Caddy vhost for Headscale.";
      }
    ])
  ];

  router-headscale-with-tailscale-eval = eval.mkNixosEvalCheck "router-headscale-with-tailscale" [
    self.nixosModules.router-headscale
    self.nixosModules.router-tailscale
    {
      services.router-headscale = {
        enable = true;
        domain = "headscale.example.com";
        openFirewall = false;
      };
      services.router-tailscale = {
        enable = true;
        authKeyFile = "/run/agenix/headscale-preauth-key";
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = builtins.elem "--login-server=https://headscale.example.com" config.services.tailscale.extraUpFlags;
        message = "router-headscale should wire router-tailscale to the Headscale login server.";
      }
      {
        assertion = config.services.tailscale.authKeyFile == "/run/agenix/headscale-preauth-key";
        message = "router-tailscale should keep the Headscale pre-auth key file.";
      }
    ])
  ];

  router-headscale-with-router-firewall-eval =
    eval.mkNixosEvalCheck "router-headscale-with-router-firewall" [
      self.nixosModules.router-firewall
      self.nixosModules.caddy-reverse-proxy
      self.nixosModules.router-headscale
      firewallWan
      {
        services.router-firewall.enable = true;
        services.caddy-router = {
          enable = true;
          domain = "example.com";
          email = "admin@example.com";
        };
        services.router-headscale = {
          enable = true;
          domain = "headscale.example.com";
        };
      }
      ({ config, ... }: assertModule [
        {
          assertion =
            builtins.elem 80 config.services.router-firewall.wanTcpPorts
            && builtins.elem 443 config.services.router-firewall.wanTcpPorts;
          message = "router-headscale should expose HTTP/HTTPS through router-firewall when Caddy is active.";
        }
      ])
    ];

  router-netbird-with-firewall-eval = eval.mkNixosEvalCheck "router-netbird-with-firewall" [
    self.nixosModules.router-firewall
    self.nixosModules.router-netbird
    firewallWan
    {
      services.router-netbird.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-firewall.overlayInterfaces == [ "nb-router" ];
        message = "router-netbird should register nb-router as an overlay interface.";
      }
      {
        assertion = config.services.router-firewall.wanUdpPorts == [ 51821 ];
        message = "router-netbird should expose its UDP port through router-firewall.";
      }
    ])
  ];

  router-netbird-without-firewall-eval = eval.mkNixosEvalCheck "router-netbird-without-firewall" [
    self.nixosModules.router-netbird
    {
      services.router-netbird.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.netbird.clients.router.interface == "nb-router";
        message = "router-netbird should configure the upstream Netbird client without router-firewall imported.";
      }
      {
        assertion = config.services.netbird.clients.router.openFirewall;
        message = "router-netbird should leave upstream firewall opening enabled when router-firewall is absent.";
      }
    ])
  ];

  router-netbird-dual-overlay-eval = eval.mkNixosEvalCheck "router-netbird-dual-overlay" [
    self.nixosModules.router-firewall
    self.nixosModules.router-tailscale
    self.nixosModules.router-netbird
    firewallWan
    {
      services.router-tailscale.enable = true;
      services.router-netbird.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion =
          builtins.elem "tailscale0" config.services.router-firewall.overlayInterfaces
          && builtins.elem "nb-router" config.services.router-firewall.overlayInterfaces;
        message = "router-tailscale and router-netbird should both register overlay interfaces.";
      }
      {
        assertion =
          builtins.elem 41641 config.services.router-firewall.wanUdpPorts
          && builtins.elem 51821 config.services.router-firewall.wanUdpPorts;
        message = "router-tailscale and router-netbird should expose distinct UDP ports.";
      }
    ])
  ];

  router-netbird-port-collision-fails-eval = eval.mkNixosEvalFailureCheck "router-netbird-port-collision" [
    self.nixosModules.router-tailscale
    self.nixosModules.router-netbird
    {
      services.router-tailscale.enable = true;
      services.router-netbird = {
        enable = true;
        port = 41641;
      };
    }
  ];

  router-netbird-dns-and-login-eval = eval.mkNixosEvalCheck "router-netbird-dns-and-login" [
    self.nixosModules.router-netbird
    {
      services.router-netbird = {
        enable = true;
        dnsResolverAddress = "127.0.0.2";
        dnsResolverPort = 1053;
        setupKeyFile = "/run/agenix/netbird-setup-key";
        setupKeyDependencies = [ "agenix.service" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.netbird.clients.router.dns-resolver.address == "127.0.0.2";
        message = "router-netbird should thread dnsResolverAddress into the Netbird client.";
      }
      {
        assertion = config.services.netbird.clients.router.dns-resolver.port == 1053;
        message = "router-netbird should thread dnsResolverPort into the Netbird client.";
      }
      {
        assertion = config.services.netbird.clients.router.login.enable;
        message = "router-netbird should enable login when setupKeyFile is set.";
      }
      {
        assertion = config.services.netbird.clients.router.login.setupKeyFile == "/run/agenix/netbird-setup-key";
        message = "router-netbird should thread setupKeyFile into the Netbird client login block.";
      }
      {
        assertion = config.services.netbird.clients.router.login.systemdDependencies == [ "agenix.service" ];
        message = "router-netbird should thread setupKeyDependencies into the Netbird client login block.";
      }
    ])
  ];

  router-zerotier-with-firewall-eval = eval.mkNixosEvalCheck "router-zerotier-with-firewall" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zerotier
    firewallWan
    {
      services.router-zerotier = {
        enable = true;
        interfaceName = "zt3jnkd4l9";
        joinNetworks = [ "a8a2c3c10c1a68de" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-firewall.overlayInterfaces == [ "zt3jnkd4l9" ];
        message = "router-zerotier should register the configured ZeroTier interface.";
      }
      {
        assertion = config.services.router-firewall.wanUdpPorts == [ 9993 ];
        message = "router-zerotier should expose its UDP port through router-firewall.";
      }
      {
        assertion = config.services.zerotierone.joinNetworks == [ "a8a2c3c10c1a68de" ];
        message = "router-zerotier should thread joinNetworks to services.zerotierone.";
      }
      {
        assertion = config.boot.kernel.sysctl."net.ipv4.ip_forward" == 1;
        message = "router-zerotier should enable IPv4 forwarding for server routing.";
      }
    ])
  ];

  router-zerotier-without-firewall-eval = eval.mkNixosEvalCheck "router-zerotier-without-firewall" [
    self.nixosModules.router-zerotier
    {
      services.router-zerotier = {
        enable = true;
        trustedInterface = false;
        joinNetworks = [ "a8a2c3c10c1a68de" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.zerotierone.enable;
        message = "router-zerotier should enable services.zerotierone without router-firewall imported.";
      }
      {
        assertion = config.services.zerotierone.port == 9993;
        message = "router-zerotier should use ZeroTier's documented default port.";
      }
    ])
  ];

  router-zerotier-trusted-interface-required-fails-eval =
    eval.mkNixosEvalFailureCheck "router-zerotier-trusted-interface-required" [
      self.nixosModules.router-zerotier
      {
        services.router-zerotier.enable = true;
      }
    ];

  router-zerotier-netbird-port-collision-fails-eval =
    eval.mkNixosEvalFailureCheck "router-zerotier-netbird-port-collision" [
      self.nixosModules.router-netbird
      self.nixosModules.router-zerotier
      {
        services.router-netbird.enable = true;
        services.router-zerotier = {
          enable = true;
          interfaceName = "zt3jnkd4l9";
          port = 51821;
        };
      }
    ];
}
