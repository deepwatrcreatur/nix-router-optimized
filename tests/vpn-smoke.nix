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
