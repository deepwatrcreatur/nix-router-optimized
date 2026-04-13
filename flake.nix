{
  description = "NixOS Router Optimizations - RouterOS-like performance features";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        }
      );

      # Custom ulogd with JSON support
      ulogdWithJson =
        pkgs:
        pkgs.ulogd.overrideAttrs (old: {
          buildInputs = old.buildInputs ++ [ pkgs.jansson ];
        });
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          router-diag = pkgs.callPackage ./pkgs/router-diag { };
          ulogd = ulogdWithJson pkgs;
        }
      );

      overlays.default = final: prev: {
        ulogd = ulogdWithJson prev;
      };

      nixosModules = {
        default = {
          imports = [
            self.nixosModules.router-networking
            self.nixosModules.router-dhcp
            self.nixosModules.router-ddns
            self.nixosModules.router-dns-service
            self.nixosModules.router-firewall
            self.nixosModules.router-log-storage
            self.nixosModules.router-pppoe
            self.nixosModules.router-homelab
            self.nixosModules.router-technitium
            self.nixosModules.router-optimizations
            self.nixosModules.router-dashboard
            self.nixosModules.router-ntopng
            self.nixosModules.router-tailscale
            self.nixosModules.router-openvpn
            self.nixosModules.router-wireguard
            self.nixosModules.nftables-fasttrack
            # Opt-in extras: all use mkEnableOption so they are safe to include
            self.nixosModules.caddy-reverse-proxy
            self.nixosModules.dns
            self.nixosModules.dns-zone
            self.nixosModules.dns-blocklists
            self.nixosModules.monitoring
            self.nixosModules.router-observability
            self.nixosModules.router-vpn
          ];
        };

        router-networking = import ./modules/router-networking.nix;
        router-dhcp = import ./modules/router-dhcp.nix;
        router-ddns = import ./modules/router-ddns.nix;
        router-dns-service = import ./modules/router-dns-service.nix;
        router-firewall = import ./modules/router-firewall.nix;
        router-log-storage = import ./modules/router-log-storage.nix;
        router-pppoe = import ./modules/router-pppoe.nix;
        router-homelab = import ./modules/router-homelab.nix;
        router-technitium = import ./modules/router-technitium.nix;
        router-optimizations = import ./modules/router-optimizations.nix;
        router-dashboard = import ./modules/router-dashboard.nix;
        router-ntopng = import ./modules/router-ntopng.nix;
        router-tailscale = import ./modules/router-tailscale.nix;
        router-openvpn = import ./modules/router-openvpn.nix;
        router-wireguard = import ./modules/router-wireguard.nix;
        nftables-fasttrack = import ./modules/nftables-fasttrack.nix;
        caddy-reverse-proxy = import ./modules/caddy-reverse-proxy.nix;
        dns = import ./modules/dns.nix;
        dns-zone = import ./modules/dns-zone.nix;
        "dns-blocklists" = import ./modules/dns-blocklists.nix;
        monitoring = import ./modules/monitoring.nix;
        router-observability = import ./modules/router-observability.nix;
        router-vpn = import ./modules/router-vpn.nix;
      };

      # Example configuration for testing
      nixosConfigurations.router-example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.router-networking
          self.nixosModules.router-dhcp
          self.nixosModules.router-ddns
          self.nixosModules.router-dns-service
          self.nixosModules.router-firewall
          self.nixosModules.router-optimizations
          self.nixosModules.router-homelab
          {
            # Minimal example configuration
            networking.hostName = "router-example";
            system.stateVersion = "25.11";
            nixpkgs.config.allowUnfree = true;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.devices = [ "nodev" ];

            services.router-networking = {
              enable = true;
              wan.device = "eth0";
              routedInterfaces.lan = {
                device = "eth1";
                ipv4Address = "192.168.1.1/24";
                dns = [ "192.168.1.1" ];
                requiredForOnline = "routable";
              };
            };

            services.router-dhcp.enable = true;
            services.router-ddns = {
              # Enable this after provisioning the token file on the target system.
              enable = false;
              cloudflare = {
                zoneName = "example.com";
                labels = [
                  "@"
                  "homelab"
                ];
                apiTokenFile = "/run/secrets/cloudflare-ddns-token";
              };
            };
            services.router-dns-service = {
              enable = true;
              provider = "unbound";
              listenAddresses = [
                "192.168.1.1"
                "127.0.0.1"
              ];
              searchDomains = [ "lan.local" ];
            };

            services.router-homelab = {
              enable = true;
              enableNtopng = true;
              sshTarget = "ssh router.example";
            };

            services.grafana.settings.security.secret_key = "router-example-insecure-dev-secret";

            # Example router configuration
            services.router-optimizations = {
              enable = true;
              interfaces = {
                wan = {
                  device = "eth0";
                  role = "wan";
                  label = "WAN";
                };
                lan = {
                  device = "eth1";
                  role = "lan";
                  label = "LAN";
                };
              };
            };
          }
        ];
      };

      nixosConfigurations.router-ddns-example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.router-ddns
          {
            networking.hostName = "router-ddns-example";
            system.stateVersion = "25.11";
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.devices = [ "nodev" ];

            services.router-ddns = {
              enable = true;
              cloudflare = {
                zoneName = "example.com";
                labels = [
                  "@"
                  "homelab"
                ];
                hostnames = [ "service.example.net" ];
                apiTokenFile = "/run/secrets/cloudflare-ddns-token";
                ttl = 1;
              };
            };
          }
        ];
      };
    };
}
