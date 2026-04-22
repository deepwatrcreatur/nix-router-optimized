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
  ageSecretStub = {
    options.age.secrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.path = lib.mkOption {
          type = lib.types.str;
        };
      });
      default = { };
    };
  };
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

  router-ha-dns-unbound-eval = eval.mkNixosEvalCheck "router-ha-dns-unbound" [
    self.nixosModules.router-ha
    self.nixosModules.router-dns-service
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
      };
      services.router-dns-service = {
        enable = true;
        provider = "unbound";
        listenAddresses = [ "127.0.0.1" ];
        serviceListenAddresses = [
          "127.0.0.1"
          "10.10.10.1"
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" == 1;
        message = "router-ha should enable IPv4 non-local bind for IPv4 VIPs.";
      }
      {
        assertion = config.services.unbound.settings.server.interface == [
          "127.0.0.1"
          "10.10.10.1"
        ];
        message = "router-dns-service should pass serviceListenAddresses to Unbound.";
      }
    ])
  ];

  router-ha-dns-technitium-eval = eval.mkNixosEvalCheck "router-ha-dns-technitium" [
    ageSecretStub
    self.nixosModules.router-ha
    self.nixosModules.router-dns-service
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
      services.router-ha = {
        enable = true;
        role = "backup";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
      };
      services.router-dns-service = {
        enable = true;
        provider = "technitium";
        serviceListenAddresses = [
          "127.0.0.1"
          "10.10.10.1"
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-technitium.listenEndPoints == [
          "127.0.0.1:53"
          "10.10.10.1:53"
        ];
        message = "router-dns-service should derive Technitium listener endpoints from serviceListenAddresses.";
      }
      {
        assertion = config.systemd.services.technitium-sync-listeners.wantedBy == [ "multi-user.target" ];
        message = "router-technitium should create a listener sync service when custom listener endpoints are declared.";
      }
    ])
  ];
}
