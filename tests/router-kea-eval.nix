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
              config.environment.etc."resolv.conf".text
              == ''
                search deepwatercreature.com
                nameserver 127.0.0.1
                nameserver 1.1.1.1
                nameserver 8.8.8.8
              '';
            message = "router-dns-service should render the router host resolv.conf search line when searchDomains are declared.";
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

  # ── Option 108 (IPv6-Only Preferred) ──────────────────────────────────────

  router-kea-option-108-enabled-eval = eval.mkNixosEvalCheck "router-kea-option-108-enabled" [
    self.nixosModules.router-networking
    self.nixosModules.router-dns-service
    self.nixosModules.router-kea
    self.nixosModules.router-nat64
    self.nixosModules.router-dns64
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
      };

      services.router-nat64.enable = true;
      services.router-dns64.enable = true;

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            { start = "10.10.200.10"; end = "10.10.200.200"; }
          ];
          ipv6OnlyPreferred.enable = true;
        };
      };
    }
    ({ config, ... }: {
      assertions =
        let
          scopeOptions = (builtins.head config.services.kea.dhcp4.settings.subnet4).option-data;
          opt108 = findOption "v6-only-preferred" scopeOptions;
          optionDefs = config.services.kea.dhcp4.settings.option-def;
        in
        [
          {
            assertion = opt108 != [ ];
            message = "router-kea option 108 should be present when ipv6OnlyPreferred is enabled.";
          }
          {
            assertion = opt108 != [ ] && (builtins.head opt108).data == "300";
            message = "router-kea option 108 should default to 300 seconds.";
          }
          {
            assertion = opt108 != [ ] && (builtins.head opt108).code == 108;
            message = "router-kea option 108 should use DHCP option code 108.";
          }
          {
            assertion = optionDefs != [ ] && (builtins.head optionDefs).code == 108;
            message = "router-kea should define custom option 108 in option-def.";
          }
        ];
    })
  ];

  router-kea-option-108-custom-timer-eval = eval.mkNixosEvalCheck "router-kea-option-108-custom-timer" [
    self.nixosModules.router-networking
    self.nixosModules.router-dns-service
    self.nixosModules.router-kea
    self.nixosModules.router-nat64
    self.nixosModules.router-dns64
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
      };

      services.router-nat64.enable = true;
      services.router-dns64.enable = true;

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            { start = "10.10.200.10"; end = "10.10.200.200"; }
          ];
          ipv6OnlyPreferred = {
            enable = true;
            v6OnlyWaitSec = 900;
          };
        };
      };
    }
    ({ config, ... }: {
      assertions =
        let
          scopeOptions = (builtins.head config.services.kea.dhcp4.settings.subnet4).option-data;
          opt108 = findOption "v6-only-preferred" scopeOptions;
        in
        [
          {
            assertion = opt108 != [ ] && (builtins.head opt108).data == "900";
            message = "router-kea option 108 should honour custom v6OnlyWaitSec timer.";
          }
        ];
    })
  ];

  router-kea-option-108-without-nat64-fails = eval.mkNixosEvalFailureCheck "router-kea-option-108-without-nat64" [
    self.nixosModules.router-networking
    self.nixosModules.router-dns-service
    self.nixosModules.router-kea
    self.nixosModules.router-nat64
    self.nixosModules.router-dns64
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
      };

      # NAT64 intentionally NOT enabled
      services.router-dns64.enable = true;

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            { start = "10.10.200.10"; end = "10.10.200.200"; }
          ];
          ipv6OnlyPreferred.enable = true;
        };
      };
    }
  ];

  router-kea-option-108-without-dns64-fails = eval.mkNixosEvalFailureCheck "router-kea-option-108-without-dns64" [
    self.nixosModules.router-networking
    self.nixosModules.router-dns-service
    self.nixosModules.router-kea
    self.nixosModules.router-nat64
    self.nixosModules.router-dns64
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
        };
      };

      services.router-dns-service = {
        enable = true;
        provider = "unbound";
      };

      services.router-nat64.enable = true;
      # DNS64 intentionally NOT enabled

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.200.0/24";
          gatewayAddress = "10.10.200.1";
          dnsServers = [ "10.10.200.1" ];
          poolRanges = [
            { start = "10.10.200.10"; end = "10.10.200.200"; }
          ];
          ipv6OnlyPreferred.enable = true;
        };
      };
    }
  ];

  router-kea-option-108-disabled-no-option-eval = eval.mkNixosEvalCheck "router-kea-option-108-disabled-no-option" [
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
            { start = "10.10.200.10"; end = "10.10.200.200"; }
          ];
        };
      };
    }
    ({ config, ... }: {
      assertions =
        let
          scopeOptions = (builtins.head config.services.kea.dhcp4.settings.subnet4).option-data;
          opt108 = findOption "v6-only-preferred" scopeOptions;
        in
        [
          {
            assertion = opt108 == [ ];
            message = "router-kea should not include option 108 when ipv6OnlyPreferred is disabled.";
          }
        ];
    })
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
