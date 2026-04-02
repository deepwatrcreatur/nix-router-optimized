{
  description = "NixOS Router Optimizations - RouterOS-like performance features";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules = {
      default = {
        imports = [
          self.nixosModules.router-networking
          self.nixosModules.router-dhcp
          self.nixosModules.router-dns-service
          self.nixosModules.router-firewall
          self.nixosModules.router-log-storage
          self.nixosModules.router-pppoe
          self.nixosModules.router-homelab
          self.nixosModules.router-technitium
          self.nixosModules.router-optimizations
          self.nixosModules.router-dashboard
          self.nixosModules.router-ntopng
          self.nixosModules.nftables-fasttrack
          # Opt-in extras: all use mkEnableOption so they are safe to include
          self.nixosModules.caddy-reverse-proxy
          self.nixosModules.dns
          self.nixosModules.dns-zone
          self.nixosModules.dns-blocklists
          self.nixosModules.monitoring
        ];
      };
      
      router-networking = import ./modules/router-networking.nix;
      router-dhcp = import ./modules/router-dhcp.nix;
      router-dns-service = import ./modules/router-dns-service.nix;
      router-firewall = import ./modules/router-firewall.nix;
      router-log-storage = import ./modules/router-log-storage.nix;
      router-pppoe = import ./modules/router-pppoe.nix;
      router-homelab = import ./modules/router-homelab.nix;
      router-technitium = import ./modules/router-technitium.nix;
      router-optimizations = import ./modules/router-optimizations.nix;
      router-dashboard = import ./modules/router-dashboard.nix;
      router-ntopng = import ./modules/router-ntopng.nix;
      nftables-fasttrack = import ./modules/nftables-fasttrack.nix;
      caddy-reverse-proxy = import ./modules/caddy-reverse-proxy.nix;
      dns = import ./modules/dns.nix;
      dns-zone = import ./modules/dns-zone.nix;
      "dns-blocklists" = import ./modules/dns-blocklists.nix;
      monitoring = import ./modules/monitoring.nix;
    };

    # Example configuration for testing
    nixosConfigurations.router-example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.router-networking
        self.nixosModules.router-dhcp
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
          services.router-dns-service = {
            enable = true;
            provider = "unbound";
            listenAddresses = [ "192.168.1.1" "127.0.0.1" ];
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
  };
}
