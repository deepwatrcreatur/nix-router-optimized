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
- **Technitium Block Lists**: Declarative DNS blocklist presets with additive custom URLs

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

### dns-blocklists
Declarative Technitium DNS blocklist management with curated presets and additive custom URLs.

## Configuration Examples

See `examples/` directory for complete working configurations.

## Technitium Block Lists

The `dns-blocklists` module manages Technitium blocklist URLs declaratively through the Technitium HTTP API.

Example:

```nix
{
  imports = [
    router-optimized.nixosModules."dns-blocklists"
  ];

  services.technitium-dns-server.enable = true;

  services.router.dnsBlockLists = {
    enable = true;
    presets = [
      "hagezi-normal"
      "hagezi-nrd-14d"
    ];
    extraUrls = [
      "https://example.com/custom-blocklist.txt"
    ];
    updateIntervalHours = 24;
  };
}
```

Available presets:
- `stevenblack`
- `oisd-big`
- `hagezi-light`
- `hagezi-normal`
- `hagezi-pro`
- `hagezi-pro-plus`
- `hagezi-ultimate`
- `hagezi-nrd-14d`

## Usage Notes

- If another flake consumes this repo, deploy tested changes by pushing them and updating that flake's lock file. A temporary `path:` input works for local debugging, but it will break pure-eval rebuilds on other hosts.
- The dashboard frontend uses browser-side layout persistence. After adding widgets or changing widget geometry, hard-refresh the page and use `Reset Layout` once if a widget appears to be missing.
- The dashboard API is intended to run threaded. Long-running endpoints such as speed tests or firewall log streaming can stall the rest of the UI if the service is downgraded to a single-threaded server.
- Service status is only meaningful for services that are actually enabled on the target host. Keep the monitored service list aligned with the host configuration instead of assuming Prometheus, Grafana, or Netdata are present everywhere.
- Technitium DNS statistics vary by API version. On the current gateway, cache hits come from `totalCached` and cache size comes from `cachedEntries`, not `totalCachedQueries`.
- Firewall log streaming and flow offload widgets need matching nftables support on the host. Without `FW-*` log rules and a runtime-created flowtable/offload rule, the dashboard will correctly show no events and `flowtable off`.
- Fail2ban integration requires the dashboard service to have access to the fail2ban control path with the right privilege model. If the widget shows offline, verify backend access first before treating it as a frontend problem.

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
