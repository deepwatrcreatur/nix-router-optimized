{
  description = "NixOS Router Optimizations - RouterOS-like performance features";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules = {
      default = {
        imports = [
          self.nixosModules.router-optimizations
          self.nixosModules.router-dashboard
          self.nixosModules.nftables-fasttrack
        ];
      };
      
      router-optimizations = import ./modules/router-optimizations.nix;
      router-dashboard = import ./modules/router-dashboard.nix;
      nftables-fasttrack = import ./modules/nftables-fasttrack.nix;
      caddy-reverse-proxy = import ./modules/caddy-reverse-proxy.nix;
      dns = import ./modules/dns.nix;
      monitoring = import ./modules/monitoring.nix;
    };

    # Example configuration for testing
    nixosConfigurations.router-example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.router-optimizations
        self.nixosModules.router-dashboard
        {
          # Minimal example configuration
          networking.hostName = "router-example";
          system.stateVersion = "25.11";
          
          # Example router configuration
          services.router-optimizations = {
            enable = true;
            wan-interface = "eth0";
            lan-interface = "eth1";
          };
        }
      ];
    };
  };
}
