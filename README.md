# NixOS Router Optimizations

A NixOS flake providing RouterOS-like performance optimizations for home/small business routers.

## Features

- **FastTrack/FastPath**: Connection tracking bypass for established connections
- **Router Networking**: Reusable systemd-networkd WAN plus routed-LAN/prefix-delegation module
- **Router DHCP**: Optional DHCP server defaults derived from routed interface definitions
- **Router DNS Service**: Provider-aware local resolver defaults for Technitium, Unbound, or Dnsmasq
- **Router Firewall**: Role-aware nftables policy derived from router interface definitions
- **Router Log Storage**: Optional persistent log/journal layout on secondary storage
- **Router PPPoE**: Composable PPPoE uplink module that can coexist with router-networking
- **Homelab Router Profile**: Opt-in dashboard, monitoring, Netdata, and common firewall defaults
- **Router Technitium**: Opt-in Technitium DNS defaults with declarative blocklist wiring
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
        router-optimized.nixosModules.router-networking
        router-optimized.nixosModules.router-dhcp
        router-optimized.nixosModules.router-dns-service
        router-optimized.nixosModules.router-firewall
        router-optimized.nixosModules.router-pppoe
        router-optimized.nixosModules.router-homelab
        router-optimized.nixosModules.router-technitium
        router-optimized.nixosModules.router-optimizations
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
              wan = { device = "ens17"; role = "wan"; label = "WAN"; bandwidth = "1Gbit"; };
              lan = { device = "ens16"; role = "lan"; label = "LAN"; };
            };
          };

          services.router-firewall = {
            enable = true;
            trustedTcpPorts = [ 80 443 ];
            wanTcpPorts = [ 80 443 ];
          };

          services.router-dhcp.enable = true;

          services.router-dns-service = {
            enable = true;
            provider = "technitium";
            searchDomains = [ "example.com" ];
          };

          services.router-homelab = {
            enable = true;
            sshTarget = "ssh router.example.com";
          };

          services.router-technitium = {
            enable = true;
            blockListPresets = [ "hagezi-normal" ];
          };
        }
      ];
    };
  };
}
```

## Modules

### router-networking
Reusable router-oriented `systemd-networkd` configuration for:
- DHCP/RA/DHCPv6-PD on WAN
- Static IPv4 WANs when DHCP is not available
- Routed downstream segments with IPv4 addresses
- VLAN-backed WAN or downstream interfaces
- IPv6 router advertisements and prefix delegation on LAN/management networks
- Stable router-facing IPv6 identities by default

### router-dhcp
Small DHCP server layer for routed routers:
- derives served segments from `services.router-networking.routedInterfaces`
- uses `systemd-networkd` DHCPServer instead of forcing a separate daemon
- supports per-segment pool sizing and static leases

### router-dns-service
Provider-aware local resolver layer:
- chooses between `technitium`, `unbound`, and `dnsmasq`
- can disable `systemd-resolved` and write a static `/etc/resolv.conf`
- integrates with `router-technitium` for blocklists and API-key export when using Technitium

### router-firewall
Role-aware nftables policy for routed routers:
- derives WAN/LAN/management interfaces from `services.router-optimizations.interfaces`
- exposes router services on trusted segments without hard-coding device names
- supports Tailscale, WAN service ports, routed forwarding, flowtable setup, MSS clamping, and hairpin NAT

Use `trustedTcpPorts` or `trustedUdpPorts` for services hosted on the router itself
that LAN/management clients should reach directly, such as Caddy on `80/443` when
split DNS points service domains at the router's LAN IP. Hairpin NAT is a fallback
for clients that bypass local DNS; it does not replace trusted input rules for
traffic terminating on the router.

### router-log-storage
Persistent log-storage layout for small router systems:
- mounts a secondary filesystem for logs
- can bind-mount `/var/log/journal` onto that volume
- creates per-service log directories with tmpfiles and a setup service

### monitoring storage placement
The monitoring module can also place state on secondary storage:
- `router.monitoring.grafanaDataDir` moves Grafana's state directory
- `router.monitoring.prometheusStateDir` changes the `/var/lib/...` state directory name Prometheus uses
- `router.monitoring.prometheusBindMountPath` bind-mounts that Prometheus state directory onto another filesystem
- `router.monitoring.waitForListenAddress = true` delays Prometheus and Grafana
  until a specific `listenAddress` exists on the host

### router-pppoe
Composable PPPoE uplink wrapper:
- uses `services.pppd` as the PPPoE client
- keeps WAN secrets out of the Nix store by referencing a runtime credentials file
- can disable direct WAN networkd management while still using `router-networking` for downstream segments

### router-homelab
Opt-in service bundle for a small homelab router:
- enables router dashboard defaults
- enables Prometheus/Grafana monitoring defaults
- enables Netdata on the primary LAN address
- can delay LAN-bound monitoring services until the chosen listen address is
  actually present with `services.router-homelab.waitForListenAddress = true`
- adds common trusted firewall ports for dashboard, Grafana, Prometheus, and Technitium when present
- adds convenient dashboard quick links such as SSH, DNS admin, Grafana, and Netdata

### router-technitium
Opt-in Technitium DNS service bundle:
- enables `services.technitium-dns-server`
- optionally exports `TECHNITIUM_API_KEY_FILE` from an age secret
- wires declarative blocklist presets through `services.router.dnsBlockLists`

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
Declarative Caddy configuration with automatic HTTPS for services:
- public or trusted-only service exposure
- root-domain redirects
- per-site reverse proxy or redirect targets

### dns-blocklists
Declarative Technitium DNS blocklist management with curated presets and additive custom URLs.

## Configuration Examples

See `examples/` directory for complete working configurations.

Additional docs:
- `docs/troubleshooting.md` for common operational failures
- `docs/IMPLEMENTATION-STATUS.md` for current module maturity
- `docs/DASHBOARD-ARCHITECTURE.md` for dashboard internals

## PPPoE Example

```nix
{
  imports = [
    router-optimized.nixosModules.router-networking
    router-optimized.nixosModules.router-pppoe
    router-optimized.nixosModules.router-firewall
  ];

  services.router-networking = {
    enable = true;
    wan.device = "ppp0";
    routedInterfaces.lan = {
      device = "lan.20";
      parentDevice = "enp2s0";
      vlanId = 20;
      ipv4Address = "10.20.0.1/24";
      dns = [ "10.20.0.1" ];
    };
  };

  services.router-pppoe = {
    enable = true;
    physicalDevice = "enp1s0";
    interfaceName = "ppp0";
    username = "isp-login";
    credentialsFile = "/run/secrets/pppoe-peer.conf";
  };
}
```

## Caddy Example

```nix
{
  imports = [
    router-optimized.nixosModules.caddy-reverse-proxy
  ];

  services.caddy-router = {
    enable = true;
    domain = "example.com";
    email = "admin@example.com";
    rootRedirect = "https://status.example.com";

    services = {
      grafana = {
        subdomain = "grafana";
        upstream = "http://10.10.10.1:3001";
      };

      homelab = {
        subdomain = "homelab";
        upstream = "http://10.10.10.1:8888";
        access = "trusted";
      };
    };
  };
}
```

## DNS Service Example

```nix
{
  imports = [
    router-optimized.nixosModules.router-dns-service
  ];

  services.router-dns-service = {
    enable = true;
    provider = "unbound";
    listenAddresses = [ "10.20.0.1" "127.0.0.1" ];
    searchDomains = [ "lan.local" ];
    localZones = {
      "router.lan.local" = "10.20.0.1";
      "nas.lan.local" = "10.20.0.10";
    };
  };
}
```

## Log Storage Example

```nix
{
  imports = [
    router-optimized.nixosModules.router-log-storage
  ];

  services.router-log-storage = {
    enable = true;
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    mountPoint = "/var/log/router";
    extraDirectories = [
      {
        name = "prometheus";
        user = "prometheus";
        group = "prometheus";
      }
      {
        name = "grafana";
        user = "grafana";
        group = "grafana";
      }
    ];
  };
}
```

## Monitoring On Secondary Storage

```nix
{
  services.router-log-storage = {
    enable = true;
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    mountPoint = "/var/log/router";
    extraDirectories = [
      { name = "grafana"; user = "grafana"; group = "grafana"; }
      { name = "prometheus"; user = "prometheus"; group = "prometheus"; }
    ];
  };

  router.monitoring = {
    enable = true;
    grafanaDataDir = "/var/log/router/grafana";
    prometheusStateDir = "router-prometheus";
    prometheusBindMountPath = "/var/log/router/prometheus";
  };
}
```

## Common WAN Policy Example

```nix
{
  services.router-firewall = {
    enable = true;

    # Useful for PPPoE and other reduced-MTU uplinks.
    tcpMssClamp.enable = true;

    # Useful when LAN clients access an internally hosted service via the
    # router's external address or a public DNS record.
    hairpinNat.enable = true;
  };
}
```

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
