{
  self,
  lib,
  eval,
}:

let
  firewallBase = {
    services.router-firewall = {
      enable = true;
      wanInterfaces = [ "wan0" ];
      lanInterfaces = [ "lan0" ];
    };
  };

  assertModule = assertions: { inherit assertions; };
in
{
  router-nat64-eval = eval.mkNixosEvalCheck "router-nat64" [
    self.nixosModules.router-firewall
    self.nixosModules.router-nat64
    firewallBase
    {
      services.router-nat64.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.tayga.enable;
        message = "router-nat64 should enable tayga.";
      }
      {
        assertion = lib.hasInfix ''iifname "nat64" accept'' config.services.router-firewall.extraForwardRules;
        message = "router-nat64 should add firewall forward rules.";
      }
    ])
  ];

  router-dns64-eval = eval.mkNixosEvalCheck "router-dns64" [
    self.nixosModules.router-nat64
    self.nixosModules.router-dns64
    self.nixosModules.dns
    {
      services.router-dns64.enable = true;
      router.dns.enable = true;
      router.dns.provider = "unbound";
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "dns64" config.services.unbound.settings.server.module-config;
        message = "router-dns64 should add dns64 module to unbound.";
      }
    ])
  ];

  router-sqm-eval = eval.mkNixosEvalCheck "router-sqm" [
    self.nixosModules.router-sqm
    {
      services.router-sqm = {
        enable = true;
        interfaces = [
          { device = "wan0"; bandwidthEgress = "100mbit"; }
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.systemd.services.apply-sqm.enable;
        message = "router-sqm should enable apply-sqm service.";
      }
    ])
  ];

  router-mdns-eval = eval.mkNixosEvalCheck "router-mdns" [
    self.nixosModules.router-mdns
    {
      services.router-mdns.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.avahi.enable && config.services.avahi.reflector;
        message = "router-mdns should enable avahi reflector.";
      }
    ])
  ];

  router-upnp-eval = eval.mkNixosEvalCheck "router-upnp" [
    self.nixosModules.router-firewall
    self.nixosModules.router-upnp
    firewallBase
    {
      services.router-upnp = {
        enable = true;
        internalIPs = [ "lan0" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.miniupnpd.enable;
        message = "router-upnp should enable miniupnpd.";
      }
      {
        assertion = lib.hasInfix "ct status dnat accept" config.services.router-firewall.extraForwardRules;
        message = "router-upnp should add ct status dnat accept rule to forward chain.";
      }
    ])
  ];

  router-bgp-eval = eval.mkNixosEvalCheck "router-bgp" [
    self.nixosModules.router-bgp
    {
      services.router-bgp = {
        enable = true;
        asn = 65001;
        neighbors."10.10.10.2" = { remoteAs = 65002; };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.frr.bgpd.enable;
        message = "router-bgp should enable frr bgpd.";
      }
      {
        assertion = builtins.elem 179 config.networking.firewall.allowedTCPPorts;
        message = "router-bgp should open BGP port 179.";
      }
    ])
  ];

  router-kea-eval = eval.mkNixosEvalCheck "router-kea" [
    self.nixosModules.router-firewall
    self.nixosModules.router-kea
    firewallBase
    {
      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.10.0/24";
          poolRanges = [ { start = "10.10.10.100"; end = "10.10.10.200"; } ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.kea.dhcp4.enable;
        message = "router-kea should enable kea-dhcp4.";
      }
      {
        assertion = config.services.kea.dhcp4.settings.subnet4 != [ ];
        message = "router-kea should configure subnet4.";
      }
    ])
  ];

  router-security-hardened-eval = eval.mkNixosEvalCheck "router-security-hardened" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    firewallBase
    {
      services.router-security-hardened = {
        enable = true;
        kernelHardening.enable = true;
        geoIpBlocking.enable = true;
        geoIpBlocking.blockedCountries = [ "cn" "ru" ];
        macSecurity.enable = true;
        macSecurity.whitelists."lan0" = [ "00:11:22:33:44:55" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.boot.kernel.sysctl."kernel.randomize_va_space" == 2;
        message = "router-security-hardened should enable ASLR.";
      }
      {
        assertion = lib.hasInfix "set blocked_countries" config.services.router-firewall.extraFilterTableRules;
        message = "router-security-hardened should add geoip sets.";
      }
      {
        assertion = config.systemd.services.update-geoip-blocklist.enable;
        message = "router-security-hardened should enable geoip update service.";
      }
      {
        assertion = lib.hasInfix "set allowed_macs_lan0" config.services.router-firewall.extraFilterTableRules;
        message = "router-security-hardened should add mac whitelists.";
      }
    ])
  ];

  router-zones-eval = eval.mkNixosEvalCheck "router-zones" [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    firewallBase
    {
      services.router-zones = {
        enable = true;
        zones = {
          wan = { interfaces = [ "wan0" ]; defaultForwardPolicy = "drop"; };
          lan = { interfaces = [ "lan0" ]; defaultForwardPolicy = "accept"; };
        };
        policies = [
          { fromZone = "lan"; toZone = "wan"; action = "accept"; }
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "chain zone_wan_policy" config.services.router-firewall.extraFilterTableRules;
        message = "router-zones should add zone chains.";
      }
      {
        assertion = lib.hasInfix "jump zone_lan_policy" config.services.router-firewall.extraForwardRules;
        message = "router-zones should add jump rules to forward chain.";
      }
    ])
  ];
}
