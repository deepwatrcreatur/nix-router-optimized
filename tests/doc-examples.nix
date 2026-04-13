{
  self,
  lib,
  pkgs,
  nixpkgs,
  system,
}:

let
  baseModule = {
    networking.hostName = "router-check";
    system.stateVersion = "25.11";
    nixpkgs.config.allowUnfree = true;

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    boot.loader.grub.devices = [ "nodev" ];
  };

  mkDocExampleCheck =
    name: modules: assertionsFn:
    let
      evaluated = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
        ] ++ modules;
      };
      config = evaluated.config;
      failed =
        (map (assertion: assertion.message) (builtins.filter (assertion: !assertion.assertion) config.assertions))
        ++ (map (assertion: assertion.message) (
          builtins.filter (assertion: !assertion.assertion) (assertionsFn config)
        ));
      result =
        if failed == [ ] then
          "ok"
        else
          throw "Doc example ${name} failed assertions:\n${lib.concatMapStringsSep "\n" (message: "- ${message}") failed}";
    in
    pkgs.runCommand "router-${name}-doc-example-eval" { } ''
      echo ${lib.escapeShellArg result} > "$out"
    '';

  readmeQuickStartModules = [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    self.nixosModules.router-dns-service
    self.nixosModules.router-firewall
    self.nixosModules.router-pppoe
    self.nixosModules.router-homelab
    self.nixosModules.router-optimizations
    {
      services.router-networking = {
        enable = true;
        wan.device = "ens17";
        routedInterfaces.lan = {
          device = "ens16";
          ipv4Address = "192.168.1.1/24";
          dns = [ "192.168.1.1" ];
          requiredForOnline = "routable";
        };
      };

      services.router-optimizations = {
        enable = true;
        interfaces = {
          wan = {
            device = "ens17";
            role = "wan";
            label = "WAN";
            bandwidth = "1Gbit";
          };
          lan = {
            device = "ens16";
            role = "lan";
            label = "LAN";
          };
        };
      };

      services.router-firewall = {
        enable = true;
        trustedTcpPorts = [
          80
          443
        ];
        wanTcpPorts = [
          80
          443
        ];
      };

      services.router-dhcp.enable = true;

      services.router-dns-service = {
        enable = true;
        provider = "technitium";
        searchDomains = [ "example.com" ];
      };

      services.router-homelab = {
        enable = true;
        enableNtopng = true;
        sshTarget = "ssh router.example.com";
      };

      services.grafana.settings.security.secret_key = "$__file{/run/agenix/grafana-secret-key}";

      services.router-technitium = {
        enable = true;
        blockListPresets = [ "hagezi-normal" ];
      };
    }
  ];
in
{
  readme-quick-start-router-eval = mkDocExampleCheck "readme-quick-start-router" (
    readmeQuickStartModules
  ) (config: [
    {
      assertion = config.systemd.network.networks."10-router-wan".matchConfig.Name == "ens17";
      message = "README quick-start should configure the documented WAN interface.";
    }
    {
      assertion = config.systemd.network.networks."20-router-lan".matchConfig.Name == "ens16";
      message = "README quick-start should configure the documented LAN interface.";
    }
    {
      assertion = config.services.router-dns-service.provider == "technitium";
      message = "README quick-start should keep the documented Technitium DNS provider.";
    }
    {
      assertion = lib.hasInfix ''iifname {"ens16"} oifname {"ens17"} accept'' config.networking.nftables.ruleset;
      message = "README quick-start should derive LAN-to-WAN firewall policy.";
    }
    {
      assertion = config.services.technitium-dns-server.enable;
      message = "README quick-start should enable Technitium through router-technitium.";
    }
  ]);

  readme-default-bundle-router-eval = mkDocExampleCheck "readme-default-bundle-router" [
    self.nixosModules.default
    {
      services.router-networking = {
        enable = true;
        wan.device = "ens17";
        routedInterfaces.lan = {
          device = "ens16";
          ipv4Address = "192.168.1.1/24";
          dns = [ "192.168.1.1" ];
        };
      };
      services.router-optimizations = {
        enable = true;
        interfaces = {
          wan = {
            device = "ens17";
            role = "wan";
            label = "WAN";
          };
          lan = {
            device = "ens16";
            role = "lan";
            label = "LAN";
          };
        };
      };
      services.router-firewall.enable = true;
      services.router-dhcp.enable = true;
      services.router-dns-service = {
        enable = true;
        provider = "unbound";
        searchDomains = [ "example.com" ];
      };
    }
  ] (config: [
    {
      assertion = config.router.dns.enable && config.router.dns.provider == "unbound";
      message = "Default module bundle should support the documented DNS service composition.";
    }
    {
      assertion = config.systemd.network.networks."20-router-lan".networkConfig.DHCPServer;
      message = "Default module bundle should support router-networking plus router-dhcp composition.";
    }
  ]);

  readme-common-wan-policy-eval = mkDocExampleCheck "readme-common-wan-policy" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "ens17" ];
        lanInterfaces = [ "ens16" ];
        tcpMssClamp.enable = true;
        hairpinNat = {
          enable = true;
          ipv4Cidrs = [ "192.168.1.0/24" ];
        };
      };
    }
  ] (config: [
    {
      assertion = lib.hasInfix "tcp option maxseg size set rt mtu" config.networking.nftables.ruleset;
      message = "README common WAN policy should render TCP MSS clamping.";
    }
    {
      assertion = lib.hasInfix ''ip daddr { 192.168.1.0/24 } masquerade'' config.networking.nftables.ruleset;
      message = "README common WAN policy should render hairpin NAT.";
    }
  ]);

  docs-router-tailscale-example-eval = mkDocExampleCheck "docs-router-tailscale-example" [
    self.nixosModules.router-tailscale
    {
      services.router-tailscale = {
        enable = true;
        authKeyFile = "/run/agenix/tailscale-auth-key";
        advertiseRoutes = [
          "10.10.0.0/16"
          "192.168.100.0/24"
        ];
        enableSsh = true;
      };
    }
  ] (config: [
    {
      assertion = config.services.tailscale.authKeyFile == "/run/agenix/tailscale-auth-key";
      message = "router-tailscale docs example should thread authKeyFile to services.tailscale.";
    }
    {
      assertion = builtins.elem "--advertise-routes=10.10.0.0/16,192.168.100.0/24" config.services.tailscale.extraUpFlags;
      message = "router-tailscale docs example should render advertised routes.";
    }
    {
      assertion = builtins.elem "--ssh" config.services.tailscale.extraUpFlags;
      message = "router-tailscale docs example should render SSH up flag.";
    }
  ]);

  docs-router-openvpn-example-eval = mkDocExampleCheck "docs-router-openvpn-example" [
    self.nixosModules.router-openvpn
    {
      services.router-openvpn.instances.roadwarrior = {
        interfaceName = "tun0";
        wanUdpPorts = [ 1194 ];
        config = ''
          dev tun0
          proto udp
          port 1194
          server 10.30.0.0 255.255.255.0
          keepalive 10 60
          persist-key
          persist-tun
          ca /run/agenix/openvpn-ca.crt
          cert /run/agenix/openvpn-server.crt
          key /run/agenix/openvpn-server.key
          dh none
          topology subnet
        '';
      };
    }
  ] (config: [
    {
      assertion = lib.hasInfix "server 10.30.0.0 255.255.255.0" config.services.openvpn.servers.roadwarrior.config;
      message = "router-openvpn docs example should configure the documented server subnet.";
    }
    {
      assertion = config.services.openvpn.servers.roadwarrior.autoStart;
      message = "router-openvpn docs example should preserve the default autostart behavior.";
    }
  ]);

  docs-router-netbird-example-eval = mkDocExampleCheck "docs-router-netbird-example" [
    self.nixosModules.router-netbird
    {
      services.router-netbird = {
        enable = true;
        setupKeyFile = "/run/agenix/netbird-setup-key";
      };
    }
  ] (config: [
    {
      assertion = config.services.netbird.clients.router.port == 51821;
      message = "router-netbird docs example should use the documented default port.";
    }
    {
      assertion = config.services.netbird.clients.router.interface == "nb-router";
      message = "router-netbird docs example should use the documented interface name.";
    }
    {
      assertion = config.services.netbird.clients.router.login.enable;
      message = "router-netbird docs example should enable login when setupKeyFile is provided.";
    }
    {
      assertion = config.services.netbird.useRoutingFeatures == "server";
      message = "router-netbird docs example should default to server routing features.";
    }
  ]);

  docs-overlay-vpn-dual-example-eval = mkDocExampleCheck "docs-overlay-vpn-dual-example" [
    self.nixosModules.router-firewall
    self.nixosModules.router-tailscale
    self.nixosModules.router-netbird
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "ens17" ];
      };
      services.router-tailscale = {
        enable = true;
        authKeyFile = "/run/agenix/tailscale-auth-key";
        advertiseRoutes = [ "10.10.0.0/16" ];
      };
      services.router-netbird = {
        enable = true;
        setupKeyFile = "/run/agenix/netbird-setup-key";
        dnsResolverAddress = "127.0.0.2";
      };
    }
  ] (config: [
    {
      assertion =
        builtins.elem "tailscale0" config.services.router-firewall.overlayInterfaces
        && builtins.elem "nb-router" config.services.router-firewall.overlayInterfaces;
      message = "overlay-vpn dual example should register both overlay interfaces.";
    }
    {
      assertion = config.services.netbird.clients.router."dns-resolver".address == "127.0.0.2";
      message = "overlay-vpn dual example should thread dnsResolverAddress to the Netbird client.";
    }
    {
      assertion =
        lib.hasInfix ''iifname "tailscale0"'' config.networking.nftables.ruleset
        && lib.hasInfix ''iifname "nb-router"'' config.networking.nftables.ruleset;
      message = "overlay-vpn dual example should render nftables rules for both overlay interfaces.";
    }
  ]);

  docs-router-wireguard-example-eval = mkDocExampleCheck "docs-router-wireguard-example" [
    self.nixosModules.router-wireguard
    {
      services.router-wireguard = {
        enable = true;
        interfaceName = "wg0";
        ips = [ "10.20.0.1/24" ];
        privateKeyFile = "/run/agenix/wg-router-key";
        peers = [
          {
            publicKey = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
            allowedIPs = [ "10.20.0.2/32" ];
            persistentKeepalive = 25;
          }
        ];
      };
    }
  ] (config: [
    {
      assertion = config.networking.wireguard.interfaces.wg0.ips == [ "10.20.0.1/24" ];
      message = "router-wireguard docs example should configure the documented interface IP.";
    }
    {
      assertion = (builtins.head config.networking.wireguard.interfaces.wg0.peers).allowedIPs == [ "10.20.0.2/32" ];
      message = "router-wireguard docs example should configure the documented peer allowed IPs.";
    }
    {
      assertion = (builtins.head config.networking.wireguard.interfaces.wg0.peers).persistentKeepalive == 25;
      message = "router-wireguard docs example should configure the documented keepalive.";
    }
  ]);
}
