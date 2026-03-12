# Basic Home Router Example

This is a simple home router configuration with:
- 1 WAN interface (DHCP)
- 1 LAN interface (static IP)
- Basic firewall with FastTrack
- Unbound DNS resolver
- Monitoring dashboard

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Enable router optimizations
  router = {
    # FastTrack firewall
    nftables-fasttrack = {
      enable = true;
      wan = "eth0";
      lan = [ "eth1" ];
      allowedTCPPorts = [ 22 ];  # SSH only
      enableFlowOffload = true;
    };

    # Performance optimizations
    optimizations = {
      enable = true;
      enableHardwareOffload = true;
      queueDiscipline = "fq_codel";
      interfaces = [ "eth0" "eth1" ];
    };

    # DNS resolver
    dns = {
      enable = true;
      provider = "unbound";
      listenAddresses = [ "192.168.1.1" ];
      upstreamServers = [ "1.1.1.1" "8.8.8.8" ];
      localZones = {
        "router.home" = "192.168.1.1";
      };
    };

    # Monitoring
    monitoring = {
      enable = true;
      interfaces = [ "eth0" "eth1" ];
      listenAddress = "192.168.1.1";
    };

    # Simple dashboard
    dashboard = {
      enable = true;
      port = 8888;
      interfaces = {
        wan = "eth0";
        lan = [ "eth1" ];
      };
    };
  };

  # Network configuration
  networking = {
    hostName = "router";
    useDHCP = false;
    nameservers = [ "127.0.0.1" ];

    interfaces = {
      eth0.useDHCP = true;  # WAN gets IP from ISP
      
      eth1.ipv4.addresses = [{
        address = "192.168.1.1";
        prefixLength = 24;
      }];
    };
  };

  # Enable IP forwarding
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # DHCP server for LAN
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config = {
        interfaces = [ "eth1" ];
      };
      subnet4 = [{
        subnet = "192.168.1.0/24";
        pools = [{
          pool = "192.168.1.100 - 192.168.1.250";
        }];
        option-data = [
          {
            name = "routers";
            data = "192.168.1.1";
          }
          {
            name = "domain-name-servers";
            data = "192.168.1.1";
          }
        ];
      }];
    };
  };

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
- **Grafana**: http://192.168.1.1:3000 (admin/admin)
- **Prometheus**: http://192.168.1.1:9090
- **SSH**: ssh admin@192.168.1.1
