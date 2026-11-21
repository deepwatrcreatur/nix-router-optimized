# NixOS Router Framework — Configuration Recipes

Practical, copyable configuration examples for common edge router scenarios using `nix-router-optimized`.

---

## Recipe 1: Minimal Single-Router Gateway

A clean, production-ready starting point for a standalone router with one WAN and one LAN interface.

```nix
{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-networking
    inputs.router-optimized.nixosModules.router-dhcp
    inputs.router-optimized.nixosModules.router-dns-service
    inputs.router-optimized.nixosModules.router-firewall
    inputs.router-optimized.nixosModules.router-optimizations
    inputs.router-optimized.nixosModules.router-homelab
  ];

  # 1. Interface and Prefix Topology
  services.router-networking = {
    enable = true;
    wan = {
      device = "eth0";
      dhcp = "yes";
      ipv6AcceptRA = true;
      dhcpv6Client = "always";
      prefixDelegationHint = "::/56";
    };
    routedInterfaces.lan = {
      device = "eth1";
      ipv4Address = "192.168.1.1/24";
      dns = [ "192.168.1.1" ];
      domains = [ "home.arpa" ];
      ipv6SendRA = true;
      dhcpPrefixDelegation = true;
    };
  };

  # 2. DHCPv4 Server on LAN
  services.router-dhcp.enable = true;

  # 3. Local DNS Resolver
  services.router-dns-service = {
    enable = true;
    provider = "unbound";
    listenAddresses = [ "192.168.1.1" "127.0.0.1" ];
    searchDomains = [ "home.arpa" ];
  };

  # 4. Firewall & FastTrack Flowtables
  services.router-firewall = {
    enable = true;
    trustedTcpPorts = [ 22 80 443 8888 ]; # SSH, Web, Dashboard
  };

  # 5. Hardware Offload Negotiation
  services.router-optimizations = {
    enable = true;
    interfaces = {
      wan = { device = "eth0"; role = "wan"; label = "WAN"; bandwidth = "1Gbit"; };
      lan = { device = "eth1"; role = "lan"; label = "LAN"; };
    };
  };

  # 6. Observability & Dashboard
  services.router-homelab = {
    enable = true;
    listenAddress = "192.168.1.1";
  };
}
```

---

## Recipe 2: PPPoE Uplink with VLAN-Tagged Downstream

For fiber or DSL connections requiring PPPoE authentication over a physical interface, with tagged VLANs on the LAN.

```nix
{ config, inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-networking
    inputs.router-optimized.nixosModules.router-pppoe
    inputs.router-optimized.nixosModules.router-firewall
    inputs.router-optimized.nixosModules.router-dhcp
  ];

  services.router-networking = {
    enable = true;
    wan.device = "ppp0";
    wan.manageWithNetworkd = false; # Handled by router-pppoe
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
    username = "isp-user@isp.net";
    credentialsFile = "/run/secrets/pppoe-peer.conf";
  };

  # Clamp MSS to account for PPPoE 8-byte overhead
  services.router-firewall = {
    enable = true;
    tcpMssClamp.enable = true;
  };
}
```

---

## Recipe 3: Dual-Node High Availability Pair with Golden MAC Cloning

To share an ISP modem that hands out only **one dynamic IP** across two router nodes over an unmanaged Layer 2 switch:

```nix
# Node A (Master)
services.router-ha = {
  enable = true;
  role = "master";
  virtualIp = "10.10.10.1/16";
  vrrpInterface = "enp6s16"; # LAN interface
  preemptDelay = 300;        # Recovered node waits 5 mins before reclaiming VIP
  wan = {
    enable = true;
    interface = "enp6s17";
    clonedMac = "02:76:c6:01:2a:b0"; # Your ISP modem's locked Golden MAC
  };
  routerAdvertisements.mode = "vrrp-owner"; # only the MASTER sends RAs
};
# Typed owners: router-ha starts these on the MASTER only.
services.router-ddns.ha.singleActiveOwner = true;
services.router-upnp.ha.singleActiveOwner = true;
# DHCP: run Kea HA on both nodes (services.router-kea.dhcp4.ha) with
# services.router-kea.ddns.ha.mode = "follow-vip"; see router-ha-ownership.md.

# Node B (Backup / Standby)
services.router-ha = {
  enable = true;
  role = "backup";
  virtualIp = "10.10.10.1/16";
  vrrpInterface = "enp1s0f1";
  preemptDelay = 300;
  wan = {
    enable = true;
    interface = "enp1s0f0";
    clonedMac = "02:76:c6:01:2a:b0";
  };
  routerAdvertisements.mode = "vrrp-owner";
};
# Same typed owners as Node A.
```

---

## Recipe 4: Caddy Reverse Proxy with Automatic HTTPS & Split DNS

Publishes internal homelab services with automated Let's Encrypt TLS certificates:

```nix
{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.caddy-reverse-proxy
  ];

  services.caddy-router = {
    enable = true;
    domain = "homelab.example.com";
    email = "admin@example.com";
    rootRedirect = "https://status.homelab.example.com";

    services = {
      grafana = {
        subdomain = "grafana";
        upstream = "http://10.10.10.1:3001";
        access = "trusted"; # Accessible only from LAN/trusted subnets
      };
      dashboard = {
        subdomain = "router";
        upstream = "http://10.10.10.1:8888";
        access = "trusted";
      };
      status = {
        subdomain = "status";
        upstream = "http://10.10.10.1:3000";
        access = "public";  # Exposed publicly
      };
    };
  };
}
```

---

## Recipe 5: Technitium DNS Blocklists & Ad-Blocking

Enables curated ad-blocking and malware domain filtering through Technitium DNS:

```nix
{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules."dns-blocklists"
    inputs.router-optimized.nixosModules.router-technitium
  ];

  services.technitium-dns-server.enable = true;

  services.router.dnsBlockLists = {
    enable = true;
    presets = [
      "hagezi-normal"
      "hagezi-nrd-14d"
      "oisd-big"
    ];
    extraUrls = [
      "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    ];
    updateIntervalHours = 24;
  };
}
```

---

## Recipe 6: Persistent Secondary Storage for Logs & Metrics

Moves volatile and write-heavy log data (systemd journal, Prometheus TSDB, Grafana sqlite) to a dedicated disk:

```nix
{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-log-storage
  ];

  services.router-log-storage = {
    enable = true;
    device = "/dev/disk/by-uuid/9eb87956-80bb-4ae5-9bc5-c82f71126574";
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
    prometheusRetentionSize = "40GB";
  };
}
```

---

## Recipe 7: Outbound Cloudflare WARP Selective Policy Routing

Routes only designated workstation or bulk downloader IPs through Cloudflare WARP while keeping everyday traffic on the native ISP link:

```nix
{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-cloudflare-warp
  ];

  services.router-cloudflare-warp = {
    enable = true;
    mode = "warp";
    routingMode = "selective-lan-ips";
    targetLanIps = [
      "10.10.11.84" # Dedicated torrent / bulk host
    ];
  };
}
```

---

## Recipe 8: Hairpin NAT & Reduced MTU Ingress

Enables Hairpin NAT (NAT loopback) and TCP MSS Clamping:

```nix
services.router-firewall = {
  enable = true;
  hairpinNat.enable = true;   # Internal clients can reach public FQDNs
  tcpMssClamp.enable = true;  # Prevents packet fragmentation on tunnel/PPPoE links
  flowtable.sipFriendly.enable = true; # Excludes SIP/RTP from fasttrack
};
```
