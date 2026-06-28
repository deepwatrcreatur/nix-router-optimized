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
  extractNotifyScript =
    key: extraConfig:
    let
      line = builtins.head (builtins.filter (lib.hasPrefix "${key} \"") (lib.splitString "\n" extraConfig));
      trimmed = lib.removePrefix "${key} \"" line;
    in
    lib.removeSuffix "\"" trimmed;
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
        assertion = lib.hasInfix ''iifname {"lan0"} oifname "nat64" accept'' config.services.router-firewall.extraForwardRules;
        message = "router-nat64 should add scoped forward-to-translation rule via adapter.";
      }
      {
        assertion = lib.hasInfix ''iifname "nat64" oifname {"wan0"} accept'' config.services.router-firewall.extraForwardRules;
        message = "router-nat64 should add scoped forward-from-translation rule via adapter.";
      }
      {
        assertion = lib.hasInfix ''iifname "nat64" accept'' config.services.router-firewall.extraInputRules;
        message = "router-nat64 should add input rules via adapter.";
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

  router-nat64-jool-opt-in-required-fails = eval.mkNixosEvalFailureCheck "router-nat64-jool-opt-in-required" [
    self.nixosModules.router-nat64
    {
      services.router-nat64 = {
        enable = true;
        translationBackend.backend = "jool-experimental";
      };
    }
  ];

  router-nat64-jool-explicit-non-support-fails = eval.mkNixosEvalFailureCheck "router-nat64-jool-explicit-non-support" [
    self.nixosModules.router-nat64
    {
      services.router-nat64 = {
        enable = true;
        translationBackend.backend = "jool-experimental";
        translationBackend.allowExperimentalJool = true;
      };
    }
  ];

  router-clat-jool-opt-in-required-fails = eval.mkNixosEvalFailureCheck "router-clat-jool-opt-in-required" [
    self.nixosModules.router-clat
    {
      services.router-clat = {
        enable = true;
        upstreamInterface = "wan0";
        listenInterfaces = [ "lan0" ];
        translationBackend.backend = "jool-experimental";
      };
    }
  ];

  router-clat-jool-explicit-non-support-fails = eval.mkNixosEvalFailureCheck "router-clat-jool-explicit-non-support" [
    self.nixosModules.router-clat
    {
      services.router-clat = {
        enable = true;
        upstreamInterface = "wan0";
        listenInterfaces = [ "lan0" ];
        translationBackend.backend = "jool-experimental";
        translationBackend.allowExperimentalJool = true;
      };
    }
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

  router-kea-ntp-eval = eval.mkNixosEvalCheck "router-kea-ntp" [
    self.nixosModules.router-kea
    {
      services.router-kea = {
        enable = true;
        dhcp4 = {
          interfaces = [ "lan0" ];
          subnet = "10.10.0.0/16";
          gatewayAddress = "10.10.10.1";
          dnsServers = [ "10.10.10.1" ];
          ntpServers = [ "10.10.10.1" ];
          poolRanges = [
            {
              start = "10.10.10.100";
              end = "10.10.10.250";
            }
          ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.any (option: option.name == "ntp-servers" && option.data == "10.10.10.1")
          (builtins.elemAt config.services.kea.dhcp4.settings.subnet4 0).option-data;
        message = "router-kea should advertise DHCP option 42 through Kea when ntpServers are set.";
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

  router-bgp-firewall-eval = eval.mkNixosEvalCheck "router-bgp-firewall" [
    self.nixosModules.router-firewall
    self.nixosModules.router-bgp
    firewallBase
    {
      services.router-firewall.extraTrustedInterfaces = [ "transit0" ];
      services.router-bgp = {
        enable = true;
        asn = 65001;
        routerId = "10.10.20.1";
        neighbors."10.10.254.2" = { remoteAs = 65010; };
        networks = [ "10.10.20.0/24" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.frr.bgpd.enable;
        message = "router-bgp should still enable frr bgpd when router-firewall is enabled.";
      }
      {
        assertion = builtins.elem 179 config.services.router-firewall.trustedTcpPorts;
        message = "router-bgp should register TCP 179 in router-firewall trustedTcpPorts.";
      }
      {
        assertion = !(builtins.elem 179 config.networking.firewall.allowedTCPPorts);
        message = "router-bgp should not use native allowedTCPPorts when router-firewall is enabled.";
      }
    ])
  ];

  router-bgp-ha-blocked-eval = eval.mkNixosEvalFailureCheck "router-bgp-ha-blocked" [
    self.nixosModules.router-ha
    self.nixosModules.router-bgp
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
      };

      services.router-bgp = {
        enable = true;
        asn = 65001;
        routerId = "10.10.10.1";
        neighbors."10.10.10.2" = { remoteAs = 65002; };
      };
    }
  ];

  # BGP+HA with singleActiveOwner should pass and produce neighbor shutdown
  router-bgp-ha-single-active-owner-eval = eval.mkNixosEvalCheck "router-bgp-ha-single-active-owner" [
    self.nixosModules.router-ha
    self.nixosModules.router-bgp
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
      };

      services.router-bgp = {
        enable = true;
        asn = 65001;
        routerId = "10.10.10.1";
        ha.singleActiveOwner = true;
        neighbors."10.10.10.2" = { remoteAs = 65002; };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.frr.bgpd.enable;
        message = "router-bgp should enable bgpd even with HA when singleActiveOwner is set.";
      }
      {
        assertion = lib.hasInfix "neighbor 10.10.10.2 shutdown" config.services.frr.config;
        message = "router-bgp should add neighbor shutdown in static config when singleActiveOwner is enabled.";
      }
    ])
  ];

  # singleActiveOwner without HA should fail
  router-bgp-single-active-without-ha-fails = eval.mkNixosEvalFailureCheck "router-bgp-single-active-without-ha" [
    self.nixosModules.router-ha
    self.nixosModules.router-bgp
    {
      services.router-bgp = {
        enable = true;
        asn = 65001;
        routerId = "10.10.10.1";
        ha.singleActiveOwner = true;
        neighbors."10.10.10.2" = { remoteAs = 65002; };
      };
    }
  ];

  router-bgp-auth-afi-policy-eval = eval.mkNixosEvalCheck "router-bgp-auth-afi-policy" [
    self.nixosModules.router-bgp
    {
      services.router-bgp = {
        enable = true;
        asn = 65001;
        routerId = "10.10.20.1";
        addressFamilies = {
          ipv4Unicast = {
            enable = true;
            networks = [ "10.10.20.0/24" ];
          };
          ipv6Unicast = {
            enable = true;
            networks = [ "fd00:20::/64" ];
          };
        };
        neighbors."10.10.254.2" = {
          remoteAs = 65010;
          description = "proxmox-frr";
          passwordFile = "/run/agenix/bgp-proxmox-password";
          addressFamilies = [
            "ipv4-unicast"
            "ipv6-unicast"
          ];
          importPolicy.ipv4Unicast = {
            allowCidrs = [ "10.10.0.0/16" ];
            defaultAction = "deny";
          };
          exportPolicy.ipv6Unicast = {
            allowCidrs = [ "fd00:20::/64" ];
            denyCidrs = [ "::/0" ];
            defaultAction = "deny";
          };
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "neighbor 10.10.254.2 password __ROUTER_BGP_SECRET_10_10_254_2__" config.services.frr.config;
        message = "router-bgp should render a runtime secret placeholder instead of embedding the BGP password.";
      }
      {
        assertion = lib.hasInfix "address-family ipv6 unicast" config.services.frr.config;
        message = "router-bgp should render explicit IPv6 unicast address-family config.";
      }
      {
        assertion = lib.hasInfix "route-map RBGP_10_10_254_2_ipv6_unicast_out deny 10" config.services.frr.config;
        message = "router-bgp should render bounded route-map policy blocks.";
      }
      {
        assertion = lib.hasInfix "/run/agenix/bgp-proxmox-password" config.systemd.services.frr.preStart;
        message = "router-bgp should consume BGP neighbor secrets from runtime files in frr preStart.";
      }
      {
        assertion = !(lib.hasInfix ''python - "$secret_value"'' config.systemd.services.frr.preStart);
        message = "router-bgp should not pass BGP secret values through a helper process argv.";
      }
      {
        assertion = lib.hasInfix "/run/frr/router-bgp-secret." config.systemd.services.frr.preStart;
        message = "router-bgp should materialize a short-lived runtime secret file before substitution.";
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
      {
        assertion = !config.services.router-dns-service.providerCapabilities.supportsAuthoritativeDnsUpdates;
        message = "Unbound should not advertise Technitium-style authoritative DDNS capabilities.";
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
      {
        assertion = config.services.router-dns-service.providerCapabilities.supportsAuthoritativeDnsUpdates;
        message = "Technitium should advertise authoritative DDNS capabilities.";
      }
    ])
  ];

  router-ha-dns-technitium-ipv6-eval = eval.mkNixosEvalCheck "router-ha-dns-technitium-ipv6" [
    ageSecretStub
    self.nixosModules.router-ha
    self.nixosModules.router-dns-service
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
      services.router-ha = {
        enable = true;
        role = "backup";
        virtualIp = "fd00::1/64";
        vrrpInterface = "lan0";
      };
      services.router-dns-service = {
        enable = true;
        provider = "technitium";
        serviceListenAddresses = [
          "::1"
          "fd00::1"
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.services.router-technitium.listenEndPoints == [
          "[::1]:53"
          "[fd00::1]:53"
        ];
        message = "router-dns-service should bracket IPv6 Technitium listener endpoints.";
      }
    ])
  ];

  router-technitium-encrypted-dns-eval = eval.mkNixosEvalCheck "router-technitium-encrypted-dns" [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
      services.router-technitium = {
        enable = true;
        encryptedDns = {
          enable = true;
          enableDnsOverHttps = true;
          dnsTlsCertificatePath = "/run/agenix/dns-encrypted.pfx";
          dnsTlsCertificatePasswordFile = "/run/agenix/dns-encrypted-password";
          webServiceTlsCertificatePath = "/run/agenix/dns-web.pfx";
          webServiceTlsCertificatePasswordFile = "/run/agenix/dns-web-password";
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.systemd.services.technitium-sync-encrypted-dns.wantedBy == [ "multi-user.target" ];
        message = "router-technitium should create an encrypted DNS sync service when encryptedDns is enabled.";
      }
      {
        assertion = config.services.router-technitium.encryptedDns.enableDnsOverHttps;
        message = "router-technitium encrypted DNS should preserve the configured DoH toggle.";
      }
      {
        assertion = !config.services.router-technitium.encryptedDns.enableDnsOverTls;
        message = "router-technitium encrypted DNS should default DoT off for a DoH-first baseline.";
      }
    ])
  ];

  router-technitium-encrypted-dns-cert-assertion = eval.mkNixosEvalFailureCheck "router-technitium-encrypted-dns-cert-assertion" [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
      services.router-technitium = {
        enable = true;
        encryptedDns = {
          enable = true;
          enableDnsOverTls = true;
          enableDnsOverHttps = false;
        };
      };
    }
  ];

  router-technitium-bootstrap-eval = eval.mkNixosEvalCheck "router-technitium-bootstrap" [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-admin-password.path = "/run/agenix/technitium-admin-password";
      services.router-technitium = {
        enable = true;
        bootstrapPasswordSecretName = "technitium-admin-password";
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.systemd.services.technitium-dns-server.environment.DNS_SERVER_ADMIN_PASSWORD_FILE == "/run/agenix/technitium-admin-password";
        message = "router-technitium should pass the bootstrap admin password file to Technitium.";
      }
      {
        assertion = config.systemd.services.technitium-bootstrap-api-token.wantedBy == [ "multi-user.target" ];
        message = "router-technitium should create a token bootstrap service when a bootstrap password secret is configured.";
      }
    ])
  ];

  router-technitium-rfc2136-eval = eval.mkNixosEvalCheck "router-technitium-rfc2136" [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
      services.router-technitium = {
        enable = true;
        rfc2136 = {
          enable = true;
          tsigKeyFile = "/run/agenix/kea-ddns-tsig-key";
          zones = [
            { name = "example.internal"; }
            {
              name = "10.10.in-addr.arpa";
              updateNetworkACL = [ "127.0.0.1" "10.10.10.0/16" ];
            }
          ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = config.systemd.services.technitium-enable-rfc2136.wantedBy == [ "multi-user.target" ];
        message = "router-technitium should create an RFC2136 sync service when RFC2136 is enabled.";
      }
      {
        assertion =
          builtins.elem "technitium-bootstrap-api-token.service" config.systemd.services.technitium-enable-rfc2136.after
          || !(config.systemd.services ? technitium-bootstrap-api-token);
        message = "router-technitium RFC2136 service should wait for token bootstrap when bootstrap mode is enabled.";
      }
      {
        assertion = config.services.router-technitium.rfc2136.tsigKeyName == "kea-ddns";
        message = "router-technitium should keep the RFC2136 TSIG key configurable through module options.";
      }
    ])
  ];

  router-ha-single-active-units-eval = eval.mkNixosEvalCheck "router-ha-single-active-units" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        enable = true;
        role = "backup";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
        singleActiveUnits = [
          "inadyn.service"
          "caddy.service"
        ];
      };
    }
    ({ config, ... }:
      let
        keepalivedConfig = config.services.keepalived.vrrpInstances.main.extraConfig;
      in
      assertModule [
        {
          assertion = config.systemd.services ? router-ha-initial-role-state;
          message = "router-ha should seed runtime role state before Keepalived starts.";
        }
        {
          assertion = config.systemd.services.router-ha-initial-role-state.before == [ "keepalived.service" ];
          message = "router-ha should seed runtime role state before Keepalived starts.";
        }
        {
          assertion = lib.hasInfix "notify_master" keepalivedConfig;
          message = "router-ha should render a master notify hook when singleActiveUnits are configured.";
        }
        {
          assertion =
            lib.hasInfix "notify_backup" keepalivedConfig
            && lib.hasInfix "notify_fault" keepalivedConfig;
          message = "router-ha should render backup and fault notify hooks when singleActiveUnits are configured.";
        }
        {
          assertion = config.systemd.services.router-ha-initial-role-state.wantedBy == [ "multi-user.target" ];
          message = "router-ha should install a boot-time role-state seeding service.";
        }
      ])
  ];
}
