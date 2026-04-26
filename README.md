# NixOS Router Optimizations

A NixOS flake providing RouterOS-like performance optimizations for home/small business routers.

## Agent Work Queue

If you are assigning or running agents against this repo, start with:

- [`docs/work-items/START-HERE.md`](docs/work-items/START-HERE.md)

## Features

- **FastTrack/FastPath**: Connection tracking bypass for established connections
- **Router Networking**: Reusable systemd-networkd WAN plus routed-LAN/prefix-delegation module
- **Router DHCP**: Optional DHCP server defaults derived from routed interface definitions
- **Router DNS Service**: Provider-aware local resolver defaults for Technitium, Unbound, or Dnsmasq
- **Router Firewall**: Role-aware nftables policy derived from router interface definitions
- **Router Log Storage**: Optional persistent log/journal layout on secondary storage
- **Router PPPoE**: Composable PPPoE uplink module that can coexist with router-networking
- **Homelab Router Profile**: Opt-in dashboard, monitoring, Netdata, and common firewall defaults
- **Router ntopng**: Optional traffic-analysis UI with router-aware interface and LAN binding defaults
- **Router Tailscale**: Optional router-aware Tailscale wrapper for subnet-router and exit-node roles
- **Router WireGuard**: Optional router-aware WireGuard wrapper for site-to-site and remote-access tunnels
- **Router OpenVPN**: Optional router-aware wrapper for declarative OpenVPN instances
- **Router Technitium**: Opt-in Technitium DNS defaults with declarative blocklist wiring
- **Technitium DHCP Reservations**: Declarative reserved leases for DHCP-managed hosts
- **Hardware Offload**: TSO, GSO, GRO, LRO optimizations
- **Advanced Queuing**: fq_codel, CAKE, BQL for optimal latency
- **XDP/eBPF**: Early packet filtering at driver level
- **nftables Fasttrack**: Flow offloading in netfilter
- **Router Dashboard**: Real-time web UI with traffic graphs, interface stats, WAN IP
- **Grafana Integration**: Pre-configured dashboards for network monitoring
- **Caddy Reverse Proxy**: Declarative HTTPS with automatic Let's Encrypt
- **Technitium Block Lists**: Declarative DNS blocklist presets with additive custom URLs
- **Kea DHCP**: ISC Kea DHCPv4 with optional RFC2136/TSIG DDNS integration (agenix-safe secret handling)
- **Router NTP**: Chrony-based NTP server with per-subnet access controls and firewall integration
- **NAT64**: Tayga-based stateless NAT64 with automatic firewall forward rules
- **DNS64**: Unbound dns64-module wiring for AAAA synthesis from A records
- **SQM**: Script-based smart queue management (fq_codel/CAKE) for WAN shaping
- **mDNS Reflector**: Avahi mDNS reflector for cross-VLAN service discovery
- **UPnP/NAT-PMP**: miniupnpd with nftables jump-rule integration
- **BGP**: FRR bgpd with declarative neighbor configuration
- **High Availability (HA)**: 
  - **VRRP (Keepalived)**: Virtual IP (VIP) sharing between master and backup router nodes.
  - **Kea DHCP HA**: Load-balancing and failover support for Kea DHCPv4.
  - **WAN HA**: Integrated "Golden MAC" cloning and interface management for seamless ISP failover when using an unmanaged switch topology.
- **Multi-WAN Failover**: Automatic health-checking and priority switching between multiple ISP uplinks.
- **WAN MAC Cloning**: Declarative MAC address spoofing for seamless ISP handover
- **Security & Hardening**:
  - **OpenBSD-tier Kernel Tuning**: Restricted dmesg, ASLR enforcement, and TCP/IP stack hardening.
  - **Geo-IP Blocking**: Declaratively block inbound traffic from specific countries via nftables.
  - **MAC Security**: Interface-specific MAC-address whitelisting with enforcement or alert policies.
- **Zone Isolation**: Declarative "Zone-based" security (WAN, LAN, IoT) with high-level cross-zone traffic policies.

## Quick Start

### As a Flake Input

...

### High Availability Setup

NixOS Router Optimizations supports advanced High Availability (HA) patterns. 

#### WAN Topology (Unmanaged Switch)
To share a single-IP ISP modem between two routers without a managed switch:
1. ISP Modem -> Unmanaged Switch
2. Router A WAN -> Unmanaged Switch
3. Router B WAN -> Unmanaged Switch

Enable `services.router-ha.wan` on both nodes. The module will ensure only the Master node has an active WAN interface and the correct "Golden MAC" expected by your ISP.

```nix
services.router-ha = {
  enable = true;
  role = "master"; # or "backup"
  virtualIp = "10.10.10.1/16";
  vrrpInterface = "enp6s18"; # LAN interface
  wan = {
    enable = true;
    interface = "enp6s17";
    clonedMac = "00:11:22:33:44:55"; # Your Golden MAC
  };
};
```

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
            enableNtopng = true;
            sshTarget = "ssh router.example.com";
          };

          services.grafana.settings.security.secret_key = "$__file{/run/agenix/grafana-secret-key}";

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
- supports optional PXE/iPXE boot advertisements per routed segment

Example PXE advertisement for an iVentoy or iPXE HTTP boot endpoint:

```nix
services.router-dhcp.interfaces.lan.pxe = {
  enable = true;
  bootServerAddress = "192.168.1.1";
  bootFilename = "http://192.168.1.1/netboot/ipxe.efi";
};
```

### router-ddns
Thin Dynamic DNS wrapper for router-hosted public ingress names:
- uses the stock NixOS `services.inadyn` service as the only backend
- supports Cloudflare API tokens from runtime files without storing tokens in
  the Nix store
- accepts inventory-style labels such as `@`, `homelab`, and `paperless`, then
  expands them under the configured Cloudflare zone

Example:

```nix
services.router-ddns = {
  enable = true;
  cloudflare = {
    zoneName = "example.com";
    labels = [ "@" "homelab" "paperless" ];
    apiTokenFile = "/run/agenix/cloudflare-ddns-token";
  };
};
```

The token file must contain the raw token string without quotes. The module
writes the quoted inadyn include file under `/run/router-ddns` at service start,
so the token is not embedded in the Nix store. A CI-visible enabled example is
available as `nixosConfigurations.router-ddns-example`.

This is intentionally narrower than general DNS ownership. Local resolver and
DHCP-driven host registration remain the responsibility of `router-dns-service`
and provider modules such as `router-technitium`.

See [`docs/router-ddns-provider-shape.md`](./docs/router-ddns-provider-shape.md)
for the Cloudflare provider option shape and inventory boundary.

### router-cloudflare-tunnel
Router-oriented wrapper for Cloudflare Tunnel using the stock NixOS
`services.cloudflared` module:
- manages named `cloudflared` tunnels declaratively
- keeps tunnel credentials in runtime files instead of the Nix store
- auto-registers Cloudflare tunnels in the router dashboard via `router-tunnels`
- derives a dashboard URL automatically when a tunnel exposes exactly one hostname

Example:

```nix
services.router-cloudflare-tunnel = {
  enable = true;
  tunnels.grafana = {
    credentialsFile = "/run/agenix/cloudflared-grafana.json";
    description = "Cloudflare Tunnel for public Grafana";
    ingress = {
      "grafana.example.com" = "http://127.0.0.1:3001";
    };
  };
};
```

This is complementary to `caddy-reverse-proxy`: Caddy still handles your local
reverse proxy and policy, while Cloudflare Tunnel can publish selected services
without opening inbound ports on the router.

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
- supports `journal.systemKeepFree` and `journal.runtimeKeepFree` so journal
  rotation starts before the secondary volume is truly full

### monitoring storage placement
The monitoring module can also place state on secondary storage:
- `router.monitoring.grafanaDataDir` moves Grafana's state directory
- `router.monitoring.prometheusStateDir` changes the `/var/lib/...` state directory name Prometheus uses
- `router.monitoring.prometheusBindMountPath` bind-mounts that Prometheus state directory onto another filesystem
- `router.monitoring.prometheusRetentionSize` adds a size cap to Prometheus TSDB
  so smaller log/state volumes do not grow without bound
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
- can enable ntopng with router-aware defaults via `services.router-homelab.enableNtopng = true`
- can delay LAN-bound monitoring services until the chosen listen address is
  actually present with `services.router-homelab.waitForListenAddress = true`
- adds common trusted firewall ports for dashboard, Grafana, Prometheus, and Technitium when present
- adds convenient dashboard quick links such as SSH, DNS admin, Grafana, and Netdata

### router-ntopng
Optional ntopng integration for routers:
- derives monitored interfaces from `services.router-optimizations.interfaces` by default
- binds the ntopng UI to the router LAN address by default
- opens the ntopng port on trusted router firewall interfaces
- plugs into the homelab dashboard/service list when `router-homelab` is used

### router-tailscale
Optional router-aware Tailscale integration:
- wraps the native `services.tailscale` module with router-oriented defaults
- configures subnet-router and exit-node flags declaratively
- plugs the Tailscale interface into `router-firewall`
- opens the Tailscale UDP port on WAN when `router-firewall` is enabled

Example:

```nix
services.router-tailscale = {
  enable = true;
  authKeyFile = "/run/agenix/tailscale-auth-key";
  advertiseRoutes = [ "10.10.0.0/16" "192.168.100.0/24" ];
  enableSsh = true;
};
```

If `router-firewall` is imported, the module also wires the Tailscale interface
into the router firewall policy. If another layer already owns Tailscale on the
host, prefer one source of truth rather than stacking multiple wrappers.

### router-openvpn
Optional router-aware OpenVPN integration:
- wraps `services.openvpn.servers` instead of replacing it
- exposes per-instance WAN TCP/UDP ports through `router-firewall`
- can treat OpenVPN tunnel interfaces as trusted router interfaces
- can allow OpenVPN clients to forward to WAN

Example:

```nix
services.router-openvpn.instances.roadwarrior = {
  interfaceName = "tun0";
  wanUdpPorts = [ 1194 ];
  config = ''
    dev tun0
    proto udp
    port 1194
    server 10.30.0.0 255.255.255.0
  '';
};
```

`trustedInterface` and `routeToWan` are opt-in. When `router-firewall` is not
imported, the module still configures OpenVPN instances but skips the router
firewall integration.

### router-wireguard
Optional router-aware WireGuard integration:
- wraps `networking.wireguard.interfaces` with a simpler router-facing option set
- opens the WireGuard UDP port on WAN through `router-firewall`
- can treat the WireGuard tunnel as a trusted router interface
- can allow WireGuard clients to forward to WAN through the router

Example:

```nix
services.router-wireguard = {
  enable = true;
  ips = [ "10.20.0.1/24" ];
  privateKeyFile = "/run/agenix/wg-router-key";
  peers = [
    {
      publicKey = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
      allowedIPs = [ "10.20.0.2/32" ];
      persistentKeepalive = 25;
    }
  ];
};
```

`trustedInterface` and `routeToWan` are opt-in. When `router-firewall` is not
imported, the module still configures WireGuard itself but skips the router
firewall wiring.

### router-technitium
Opt-in Technitium DNS service bundle:
- enables `services.technitium-dns-server`
- optionally exports `TECHNITIUM_API_KEY_FILE` from an age secret
- wires declarative blocklist presets through `services.router.dnsBlockLists`
- can add declarative DHCP reservations through `services.router-technitium.dhcpReservations`

Example:

```nix
services.router-technitium = {
  enable = true;
  dhcpReservations.authentik-host = {
    scope = "LAN";
    macAddress = "BC:24:11:A4:01:6F";
    ipAddress = "10.10.11.70";
    hostName = "authentik-host";
    comments = "Dedicated Authentik identity host";
  };
};
```

The current reservation sync is intentionally conservative:
- missing reservations are created automatically
- existing conflicting reservations are left unchanged and logged instead of being mutated blindly

### router-optimizations
Core performance optimizations including kernel tuning, hardware offloads, and queue management.

### router-dashboard
Web dashboard on port 8888 showing:
- Real-time interface bandwidth (RX/TX)
- WAN IP address
- Interface status and IPs
- System uptime and connections
- VPN status
- Declarative tunnel status (zrok, ngrok, Cloudflare Tunnel, Tailscale Funnel, etc.)
- Declarative remote administration status (Guacamole, MeshCentral, SSH, IPMI/iDRAC/iLO, etc.)

The dashboard discovers tunnel and remote-admin entries from metadata-only
modules. These modules do not manage the underlying services; they simply
describe existing systemd units and endpoints so the dashboard can render status
consistently.

Example:

```nix
{
  imports = [
    router-optimized.nixosModules.router-dashboard
    router-optimized.nixosModules.router-tunnels
    router-optimized.nixosModules.router-remote-admin
  ];

  services.router-dashboard.enable = true;

  services.router-tunnels = {
    enable = true;
    tunnels = [
      {
        name = "grafana-share";
        provider = "cloudflare";
        unit = "cloudflared-grafana.service";
        publicUrl = "https://grafana.example.com";
        description = "Cloudflare Tunnel for external Grafana access";
      }
      {
        name = "support-zrok";
        provider = "zrok";
        unit = "zrok-share-support.service";
        description = "Ephemeral support tunnel";
      }
    ];
  };

  services.router-remote-admin = {
    enable = true;
    entries = [
      {
        name = "guac";
        kind = "guacamole";
        unit = "guacd.service";
        url = "https://guac.example.com";
        description = "Browser-based remote desktop gateway";
      }
      {
        name = "bastion";
        kind = "ssh";
        unit = "sshd.service";
        url = "ssh://router.example.com";
        description = "Primary SSH bastion";
      }
    ];
  };
}
```

Status rules:
- tunnels are `up` when the backing unit is active and a `publicUrl` is known
- remote-admin entries are `up` when the backing unit is active and a `url` is known
- active services without a URL are shown as `warning`
- inactive services are shown as `down`

### nftables-fasttrack
Flow offloading configuration for nftables to bypass connection tracking for established flows.

### caddy-reverse-proxy
Declarative Caddy configuration with automatic HTTPS for services:
- public or trusted-only service exposure
- root-domain redirects
- per-site reverse proxy or redirect targets

### dns-blocklists
Declarative Technitium DNS blocklist management with curated presets and additive custom URLs.

### router-kea
ISC Kea DHCPv4 with optional RFC2136/TSIG DDNS to register leases in a local DNS server. The
TSIG secret is injected at runtime via an `ExecStartPre` script so it never enters the Nix store.

```nix
services.router-kea = {
  enable = true;
  dhcp4 = {
    subnet = "10.10.0.0/16";
    gatewayAddress = "10.10.10.1";
    dnsServers = [ "10.10.10.1" ];
    poolRanges = [{ start = "10.10.10.100"; end = "10.10.10.250"; }];
    reservations = [
      { hw-address = "aa:bb:cc:dd:ee:ff"; ip-address = "10.10.10.50"; hostname = "myhost"; }
    ];
  };
  ddns = {
    enable = true;
    tsigKeyFile = config.age.secrets.kea-ddns-tsig-key.path;
    forwardZone = "home.example.com";
    reverseZone = "10.10.in-addr.arpa";
  };
};
```

### router-ntp
Chrony NTP server with declarative upstream servers, per-subnet client access controls, and
optional firewall integration (opens UDP 123 on trusted interfaces when router-firewall is loaded).

```nix
services.router-ntp = {
  enable = true;
  lanSubnets = [ "10.10.0.0/16" "10.20.0.0/24" ];
};
```

### router-nat64
Stateless NAT64 via Tayga. Automatically adds an nftables forward rule for the nat64 tunnel
interface when `router-firewall` is loaded. Use the Well-Known Prefix (`64:ff9b::/96`) or a
custom ULA prefix.

```nix
services.router-nat64 = {
  enable = true;
  # Defaults: ipv6Prefix = "64:ff9b::/96", ipv4Pool = "192.168.255.0/24"
};
```

Pair with `router-dns64` for full NAT64 operation (requires `router-dns-service.provider = "unbound"`):

```nix
services.router-dns64.enable = true;
# prefix auto-derives from router-nat64.ipv6Prefix
```

### router-sqm
Smart queue management for WAN uplink shaping. Wraps `tc` with fq_codel/CAKE via a
declarative interface list.

```nix
services.router-sqm = {
  enable = true;
  interfaces = [
    { device = "ppp0"; bandwidthEgress = "900mbit"; bandwidthIngress = "500mbit"; }
  ];
};
```

### router-mdns
Avahi mDNS reflector. Enables cross-VLAN discovery (Chromecast, AirPlay, etc.) by reflecting
mDNS traffic between specified interfaces.

```nix
services.router-mdns = {
  enable = true;
  interfaces = [ "enp6s16" "enp6s16.20" "enp6s16.30" ];
};
```

### router-upnp
miniupnpd UPnP/NAT-PMP server with nftables integration. Adds a `jump miniupnpd` forward rule
when `router-firewall` is loaded.

```nix
services.router-upnp = {
  enable = true;
  internalIPs = [ "enp6s16" ];
  # externalInterface defaults to services.router-networking.wan.device
};
```

### router-bgp
FRR bgpd with declarative neighbor configuration. Opens TCP 179 in `networking.firewall`.

```nix
services.router-bgp = {
  enable = true;
  asn = 65001;
  neighbors."10.10.10.2" = { remoteAs = 65002; };
};
```

### router-security-hardened
Optional "OpenBSD-tier" security hardening for high-risk or public-facing routers:
- **Kernel Hardening**: ASLR enforcement, restricted dmesg, module disabling, and TCP/IP stack protections.
- **Geo-IP Blocking**: Declaratively block inbound traffic from specific countries (e.g., `["cn" "ru"]`) using nftables sets.
- **MAC Security**: Interface-specific MAC-address whitelisting with enforcement or alert-only modes.

Example:

```nix
services.router-security-hardened = {
  enable = true;
  kernelHardening.enable = true;
  geoIpBlocking = {
    enable = true;
    blockedCountries = [ "cn" "ru" ];
  };
  macSecurity = {
    enable = true;
    whitelists.ens16 = [ "00:11:22:33:44:55" ];
  };
};
```

### router-zones
Declarative zone-based firewall policy management, simplifying complex VLAN isolation:
- Defines security "Zones" (WAN, LAN, IoT, Guest) as groups of interfaces.
- Sets high-level default policies (Accept/Drop/Reject) for input and forward traffic.
- Implements declarative cross-zone traffic rules.

Example:

```nix
services.router-zones = {
  enable = true;
  zones = {
    wan = { interfaces = [ "wan0" ]; defaultForwardPolicy = "drop"; };
    lan = { interfaces = [ "lan0" ]; defaultForwardPolicy = "accept"; };
    iot = { interfaces = [ "lan0.20" ]; defaultForwardPolicy = "drop"; };
  };
  policies = [
    { fromZone = "lan"; toZone = "wan"; action = "accept"; }
    { fromZone = "iot"; toZone = "wan"; action = "accept"; }
    {
      fromZone = "iot";
      toZone = "lan";
      action = "drop";
      extraRules = "ip daddr 10.10.10.50 tcp dport 8123 accept comment \"Allow IoT to Home Assistant\"";
    }
  ];
};
```

## Configuration Examples

See `examples/` directory for complete working configurations.

Additional docs:
- `docs/troubleshooting.md` for common operational failures
- `docs/IMPLEMENTATION-STATUS.md` for current module maturity
- `docs/DASHBOARD-ARCHITECTURE.md` for dashboard internals
- `docs/router-nat64-dns64.md` for NAT64 + DNS64 setup and verification

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
