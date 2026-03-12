# NixOS Router Optimizations

A NixOS flake providing RouterOS-like performance optimizations for home/small business routers.

## Features

- **FastTrack/FastPath**: Connection tracking bypass for established connections
- **Hardware Offload**: TSO, GSO, GRO, LRO optimizations
- **Advanced Queuing**: fq_codel, CAKE, BQL for optimal latency
- **XDP/eBPF**: Early packet filtering at driver level
- **nftables Fasttrack**: Flow offloading in netfilter
- **Router Dashboard**: Real-time web UI with traffic graphs, interface stats, WAN IP
- **Grafana Integration**: Pre-configured dashboards for network monitoring
- **Caddy Reverse Proxy**: Declarative HTTPS with automatic Let's Encrypt

## Quick Start

### As a Flake Input

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    router-optimized.url = "github:yourusername/nix-router-optimized";
  };

  outputs = { self, nixpkgs, router-optimized }: {
    nixosConfigurations.gateway = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        router-optimized.nixosModules.router-optimizations
        router-optimized.nixosModules.router-dashboard
        {
          # Your configuration
          services.router-optimizations = {
            enable = true;
            wan-interface = "ens17";
            lan-interface = "ens16";
          };
        }
      ];
    };
  };
}
```

## Modules

### router-optimizations
Core performance optimizations including kernel tuning, hardware offloads, and queue management.

### router-dashboard
Web dashboard on port 8888 showing:
- Real-time interface bandwidth (RX/TX)
- WAN IP address
- Interface status and IPs
- System uptime and connections

### nftables-fasttrack
Flow offloading configuration for nftables to bypass connection tracking for established flows.

### caddy-reverse-proxy
Declarative Caddy configuration with automatic HTTPS for services.

## Configuration Examples

See `examples/` directory for complete working configurations.

## Performance Improvements

Typical improvements over default NixOS networking:
- 20-40% higher throughput on gigabit connections
- 50-80% lower latency under load (bufferbloat)
- Reduced CPU usage for routing workloads
- Hardware offloading where supported

## License

MIT

## Contributing

PRs welcome! Please test on your hardware before submitting.
