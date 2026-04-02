# Basic Home Router Example

This is a simple home router configuration with:
- 1 WAN interface (DHCP)
- 1 LAN interface (static IP)
- Basic firewall with FastTrack
- Unbound DNS resolver
- Monitoring dashboard and homelab service bundle

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    router-optimized.nixosModules.router-networking
    router-optimized.nixosModules.router-dhcp
    router-optimized.nixosModules.router-firewall
    router-optimized.nixosModules.router-homelab
    router-optimized.nixosModules.router-optimizations
  ];

  services = {
    router-networking = {
      enable = true;
      wan.device = "eth0";
      routedInterfaces.lan = {
        device = "eth1";
        ipv4Address = "192.168.1.1/24";
        dns = [ "192.168.1.1" ];
        requiredForOnline = "routable";
      };
    };

    router-firewall = {
      enable = true;
      wanTcpPorts = [ 22 ];
    };

    router-dhcp.enable = true;

    router-homelab = {
      enable = true;
      enableNtopng = true;
      sshTarget = "ssh admin@192.168.1.1";
    };

    router-optimizations = {
      enable = true;
      interfaces = {
        wan = {
          device = "eth0";
          role = "wan";
          label = "WAN";
          bandwidth = "1Gbit";
        };
        lan = {
          device = "eth1";
          role = "lan";
          label = "LAN";
        };
      };
    };

  };

  networking.hostName = "router";
  networking.nameservers = [ "127.0.0.1" ];

  # Basic services
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  # User account
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... your-key-here"
    ];
  };

  # Sudo without password
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
```

## Usage

1. Replace `eth0` and `eth1` with your actual interface names
2. Add your SSH public key
3. Build and deploy:

```bash
nixos-rebuild switch --flake .#router
```

## Access

- **Router Dashboard**: http://192.168.1.1:8888
- **Grafana**: http://192.168.1.1:3001 (admin/admin)
- **ntopng**: http://192.168.1.1:3000
- **Prometheus**: http://192.168.1.1:9090
- **SSH**: ssh admin@192.168.1.1
