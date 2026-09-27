{
  self,
  lib,
  pkgs,
}:

let
  mkRouterTest = import ./lib/mk-router-test.nix {
    inherit pkgs lib self;
  };
in
mkRouterTest {
  name = "router-basic-smoke";

  nodes = {
    wanSimulator = { pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-wan" = {
        matchConfig.Name = "eth1";
        address = [ "198.51.100.1/24" ];
      };
      services.dnsmasq = {
        enable = true;
        settings = {
          interface = "eth1";
          bind-interfaces = true;
          listen-address = "198.51.100.1";
          address = [
            "/wan.simulator/198.51.100.1"
            "/example.com/198.51.100.1"
          ];
        };
      };
      environment.systemPackages = [ pkgs.iputils ];
    };

    router = { pkgs, ... }: {
      imports = [
        self.nixosModules.default
      ];

      virtualisation.vlans = [ 1 2 3 ];
      virtualisation.memorySize = 1536;

      systemd.network.enable = true;

      services.router-networking = {
        enable = true;
        wan = {
          device = "eth1";
          mode = "static";
          ipv4Address = "198.51.100.2/24";
          gateway4 = "198.51.100.1";
          metric = 10;
          dns = [ "198.51.100.1" ];
        };
        routedInterfaces = {
          lan = {
            device = "eth2";
            ipv4Address = "10.0.10.1/24";
            dns = [ "10.0.10.1" ];
          };
          iot = {
            device = "eth3";
            ipv4Address = "10.0.20.1/24";
            dns = [ "10.0.20.1" ];
          };
        };
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth1" ];
        lanInterfaces = [ "eth2" "eth3" ];
        enableIpv4Masquerade = true;
      };

      services.router-zones = {
        enable = true;
        zones = {
          wan = {
            interfaces = [ "eth1" ];
          };
          lan = {
            interfaces = [ "eth2" ];
            defaultForwardAction = "drop";
          };
          iot = {
            interfaces = [ "eth3" ];
            defaultForwardAction = "drop";
          };
        };
        policies = [
          {
            fromZone = "lan";
            toZone = "wan";
            action = "accept";
          }
          {
            fromZone = "iot";
            toZone = "wan";
            action = "accept";
          }
        ];
      };

      services.router-dhcp = {
        enable = true;
        interfaces = {
          lan = {
            enable = true;
            poolOffset = 50;
            poolSize = 50;
          };
          iot = {
            enable = true;
            poolOffset = 50;
            poolSize = 50;
          };
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
        serviceListenAddresses = [ "127.0.0.1" "10.0.10.1" "10.0.20.1" ];
        upstreamServers = [ "198.51.100.1" ];
        localZones = {
          "router.internal" = "10.0.10.1";
        };
      };

      services.router-slices.enable = true;

      services.unbound.settings.server = {
        val-permissive-mode = "yes";
        module-config = "\"iterator\"";
      };

      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.routerctl
        pkgs.iputils
      ];
    };

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 2 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-lan" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config = {
          RouteMetric = 10;
          UseDNS = true;
        };
      };
      environment.systemPackages = [ pkgs.iputils pkgs.dnsutils ];
    };

    iotNode = { pkgs, ... }: {
      virtualisation.vlans = [ 3 ];
      networking = {
        useNetworkd = true;
        firewall.enable = false;
      };
      systemd.network.networks."10-iot" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config = {
          RouteMetric = 10;
          UseDNS = true;
        };
      };
      environment.systemPackages = [ pkgs.iputils pkgs.dnsutils ];
    };
  };

  testScript = ''
    start_all()

    wanSimulator.wait_for_unit("systemd-networkd.service")
    wanSimulator.wait_for_unit("dnsmasq.service")

    router.wait_for_unit("systemd-networkd.service")
    router.wait_for_unit("nftables.service")
    router.wait_for_unit("unbound.service")

    client.wait_for_unit("systemd-networkd.service")
    iotNode.wait_for_unit("systemd-networkd.service")

    # Invariant 1: DHCP Lease Acquisition
    client.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 10.0.10.'")
    iotNode.wait_until_succeeds("ip -4 addr show dev eth1 | grep -q 'inet 10.0.20.'")

    # Invariant 2: LAN Gateway Ping
    client.succeed("ping -c 2 10.0.10.1")

    # Invariant 3: Internet Egress & NAT Masquerade
    client.succeed("ping -c 2 198.51.100.1")

    # Invariant 4: Local & Forward DNS Resolution
    client.succeed("host -t A router.internal 10.0.10.1")
    client.succeed("host -t A wan.simulator 10.0.10.1")

    # Invariant 5: IoT Node Egress to WAN
    iotNode.succeed("ping -c 2 198.51.100.1")

    # Invariant 6: Zone Isolation (IoT client cannot access LAN client)
    client_ip = client.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    iotNode.fail(f"ping -c 2 -W 1 {client_ip}")

    # Invariant 7: routerctl CLI Inspection
    router.succeed("routerctl status --json")
    router.succeed("routerctl firewall summary --json")
    router.succeed("routerctl firewall explain lan wan --json")
  '';
}
