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
          self.nixosModules.router-optimizations
          self.nixosModules.router-dashboard
          self.nixosModules.nftables-fasttrack
        ];
      };
      
      router-networking = import ./modules/router-networking.nix;
      router-optimizations = import ./modules/router-optimizations.nix;
      router-dashboard = import ./modules/router-dashboard.nix;
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
        self.nixosModules.router-optimizations
        self.nixosModules.router-dashboard
        {
          # Minimal example configuration
          networking.hostName = "router-example";
          system.stateVersion = "25.11";
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
