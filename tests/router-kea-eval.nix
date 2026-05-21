{
  self,
  eval,
  ...
}:

let
  findOption = name: optionData: builtins.filter (opt: opt.name == name) optionData;
in
{
  router-kea-search-domains-eval = eval.mkNixosEvalCheck "router-kea-search-domains" [
    self.nixosModules.router-networking
    self.nixosModules.router-dns-service
    self.nixosModules.router-ntp
    self.nixosModules.router-kea
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
          domains = [ "deepwatercreature.com" ];
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
        searchDomains = [ "deepwatercreature.com" ];
      };

      services.router-ntp.enable = true;

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            {
              start = "10.10.200.1";
              end = "10.10.200.200";
            }
          ];
        };
      };
    }
    ({ config, ... }: {
      assertions =
        let
          scopeOptions = (builtins.head config.services.kea.dhcp4.settings.subnet4).option-data;
        in
        [
          {
            assertion =
              (findOption "domain-name" scopeOptions) != [ ]
              && (builtins.head (findOption "domain-name" scopeOptions)).data == "deepwatercreature.com";
            message = "router-kea should advertise DHCP option 15 domain-name.";
          }
          {
            assertion =
              (findOption "domain-search" scopeOptions) != [ ]
              && (builtins.head (findOption "domain-search" scopeOptions)).data == "deepwatercreature.com";
            message = "router-kea should advertise DHCP option 119 domain-search.";
          }
          {
            assertion =
              (findOption "ntp-servers" scopeOptions) != [ ]
              && (builtins.head (findOption "ntp-servers" scopeOptions)).data == "10.10.200.1";
            message = "router-kea should advertise DHCP option 42 NTP servers when router-ntp is enabled.";
          }
        ];
    })
  ];

  router-kea-invalid-network-address-pool-fails = eval.mkNixosEvalFailureCheck "router-kea-invalid-network-address-pool" [
    self.nixosModules.router-networking
    self.nixosModules.router-kea
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
        };
      };

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            {
              start = "10.10.200.0";
              end = "10.10.200.200";
            }
          ];
        };
      };
    }
  ];

  router-kea-ntp-fallback-requires-allowed-subnet = eval.mkNixosEvalCheck "router-kea-ntp-fallback-requires-allowed-subnet" [
    self.nixosModules.router-networking
    self.nixosModules.router-ntp
    self.nixosModules.router-kea
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "192.168.50.1/24";
        };
      };

      services.router-ntp.enable = true;

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "192.168.50.0/24";
          gatewayAddress = "192.168.50.1";
          dnsServers = [ "192.168.50.1" ];
          poolRanges = [
            {
              start = "192.168.50.10";
              end = "192.168.50.200";
            }
          ];
        };
      };
    }
    ({ config, ... }: {
      assertions =
        let
          scopeOptions = (builtins.head config.services.kea.dhcp4.settings.subnet4).option-data;
        in
        [
          {
            assertion = (findOption "ntp-servers" scopeOptions) == [ ];
            message = "router-kea should not auto-advertise DHCP option 42 when router-ntp does not allow the served subnet.";
          }
        ];
    })
  ];
}
