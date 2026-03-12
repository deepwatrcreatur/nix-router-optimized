# Router Flake Integration Guide

## Overview

The `nix-router-optimized` flake has been successfully created and integrated into the `unified-nix-configuration` repository for the gateway host.

## What Was Done

### 1. Created Modular Router Flake
Created a standalone flake at `/home/deepwatrcreatur/flakes/nix-router-optimized` with:
- **Networking module**: Interface configuration, NAT, IPv6
- **Firewall module**: nftables with fasttrack offloading
- **Optimizations module**: Hardware offload, XDP, queue management
- **Monitoring module**: Netdata, Prometheus, Grafana, custom dashboard
- **Main module**: Combines all features with simple configuration options

### 2. Integrated into Gateway
Modified `unified-nix-configuration` to use the flake:
- Added flake input in `flake.nix`
- Replaced local modules with `inputs.nix-router-optimized.nixosModules.default`
- Configured gateway-specific settings in `hosts/nixos/gateway/default.nix`

### 3. Gateway Configuration
The gateway now uses declarative configuration for:
- **WAN**: ens17 (DHCP with IPv6)
- **LAN**: ens16 (10.10.10.1/16 with DHCPv4/v6)
- **Management**: ens18 (192.168.100.100/24)
- **Monitoring**: Netdata (8080), Grafana (3000), Custom dashboard (8888)
- **Reverse Proxy**: Caddy with automatic Let's Encrypt for deepwatercreature.com

## Router Features

### Performance Optimizations
- **FastTrack**: nftables flow offloading for established connections
- **Hardware Offload**: TSO, GSO, GRO, LRO enabled
- **XDP**: Early packet filtering at driver level
- **Queue Management**: fq_codel for better latency under load
- **Connection Tracking**: Optimized for router workloads

### Monitoring Stack
- **Netdata**: Real-time system monitoring (port 8080)
- **Prometheus**: Metrics collection and storage (port 9090)
- **Grafana**: Visualization and dashboards (port 3000)
- **Custom Dashboard**: Router-specific interface stats (port 8888)

### Security
- **nftables**: Modern firewall with stateful packet filtering
- **Fail2ban**: SSH brute-force protection
- **Trusted Interfaces**: LAN and management interfaces trusted
- **WAN Hardening**: Default deny policy on WAN

## Configuration Example

```nix
services.router = {
  enable = true;
  
  wan = {
    interface = "ens17";
    ipv6 = true;
  };
  
  lan = {
    interface = "ens16";
    ipAddress = "10.10.10.1";
    prefixLength = 16;
    ipv6 = true;
  };
  
  optimizations.enable = true;
  monitoring.enable = true;
  firewall.enable = true;
};
```

## Next Steps

### For Gateway
1. Pull latest changes on gateway: `cd ~/flakes/unified-nix-configuration && git pull`
2. Rebuild: `update` (uses remote builder on attic-cache)
3. Test dashboards:
   - http://10.10.10.1:8080 (Netdata)
   - http://10.10.10.1:3000 (Grafana - default: admin/admin)
   - http://10.10.10.1:8888 (Custom router dashboard)

### For Router Flake
1. Publish to GitHub: `cd /home/deepwatrcreatur/flakes/nix-router-optimized && git init && git remote add origin <url>`
2. Update flake input to use `github:` URL instead of `path:`
3. Add more dashboard templates for Grafana
4. Add support for VLANs and multiple LANs
5. Add traffic shaping/QoS modules

## Known Issues

### Dashboard Issues
- **Custom dashboard (8888)** shows interface status but may have issues with:
  - WAN IP detection
  - RX/TX rate calculations
  - Needs testing after rebuild

### DNS Resolution
- Gateway should use Technitium DNS (127.0.0.1:53) for local resolution
- `/etc/resolv.conf` may be empty but DNS works via systemd-resolved

### Spinning Disk Logging
- Log directories configured on `/var/log/gateway`
- Using `nofail` mount option to prevent boot issues
- Technitium logs need proper user permissions

## Troubleshooting

### Check if remote builder is working
```bash
nix build --builders 'ssh://root@10.10.11.39 x86_64-linux' --print-build-logs
```

### Check dashboard services
```bash
systemctl status netdata prometheus grafana router-dashboard
```

### Check firewall rules
```bash
sudo nft list ruleset
```

### Check interface status
```bash
ip addr show
ip route show
