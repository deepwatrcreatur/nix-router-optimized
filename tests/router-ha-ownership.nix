{
  self,
  lib,
  eval,
}:

# Typed VRRP ownership for RAs, DDNS (inadyn and Kea D2) and UPnP: what each
# option renders, and which unowned combinations fail evaluation.
let
  pair =
    {
      ha ? { },
      extra ? { },
    }:
    [
      self.nixosModules.router-networking
      self.nixosModules.router-ha
      self.nixosModules.router-ddns
      self.nixosModules.router-upnp
      self.nixosModules.router-kea
      (lib.recursiveUpdate {
        services.router-networking = {
          enable = true;
          wan.device = "wan0";
          routedInterfaces.lan = {
            device = "lan0";
            ipv4Address = "10.10.10.2/24";
          };
        };
        services.router-ha = lib.recursiveUpdate {
          enable = true;
          role = "master";
          vrrpPasswordFile = "/run/keys/vrrp-password";
          virtualIp = "10.10.10.1/24";
          vrrpInterface = "lan0";
        } ha;
      } extra)
    ];

  ddns = {
    services.router-ddns = {
      enable = true;
      cloudflare = {
        zoneName = "example.net";
        labels = [ "home" ];
        apiTokenFile = "/run/keys/cloudflare";
      };
    };
  };

  upnp.services.router-upnp = {
    enable = true;
    internalIPs = [ "lan0" ];
  };

  kea = d2: {
    services.router-kea = {
      enable = true;
      dhcp4 = {
        interfaces = [ "lan0" ];
        subnet = "10.10.10.0/24";
        gatewayAddress = "10.10.10.1";
        poolRanges = [
          {
            start = "10.10.10.100";
            end = "10.10.10.199";
          }
        ];
      };
      ddns = lib.recursiveUpdate {
        enable = true;
        tsigKeyFile = "/run/keys/kea-ddns";
        forwardZone = "example.net";
      } d2;
    };
  };

  keaHa = {
    services.router-kea.dhcp4.ha = {
      enable = true;
      thisServerName = "router-a";
      peerName = "router-b";
      role = "primary";
      localAddress = "10.10.10.2";
      peerAddress = "10.10.10.3";
    };
  };

  raOwner.routerAdvertisements.mode = "vrrp-owner";

  check = name: modules: assertions: eval.mkNixosEvalCheck name (modules ++ [ ({ config, ... }: { assertions = assertions config; }) ]);
in
{
  router-ha-ownership-eval =
    check "router-ha-ownership"
      (pair {
        ha = raOwner;
        extra = lib.foldl' lib.recursiveUpdate { } [
          ddns
          upnp
          (kea { ha.mode = "single-active"; })
          {
            services.router-ddns.ha.singleActiveOwner = true;
            services.router-upnp.ha.singleActiveOwner = true;
          }
        ];
      })
      (
        config:
        let
          units = config.services.router-ha.singleActiveUnits;
          svc = config.systemd.services;
        in
        [
          {
            assertion = config.services.router-ha.vrrpNetwork == "20-router-lan"
              && config.systemd.network.networks."20-router-lan".networkConfig.KeepConfiguration == "static";
            message = "the VRRP network must keep the VIP across networkd reconfigures (KeepConfiguration=static).";
          }
          {
            assertion =
              let
                lan = config.systemd.network.networks."20-router-lan";
              in
              lan.networkConfig.IPv6SendRA == true && lan.ipv6SendRAConfig.RouterLifetimeSec == 0;
            message = "vrrp-owner must keep RAs on with router lifetime 0 in the static LAN config.";
          }
          {
            assertion = lib.all (u: lib.elem u units) [
              "router-ha-ra-owner.service"
              "inadyn.timer"
              "inadyn.service"
              "miniupnpd.service"
              "kea-dhcp-ddns-server.service"
            ];
            message = "typed owners must register their units with router-ha (got ${toString units}).";
          }
          {
            assertion =
              config.systemd.timers.inadyn.wantedBy == [ ]
              && svc.inadyn.wantedBy == [ ]
              && svc.miniupnpd.wantedBy == [ ]
              && svc.kea-dhcp-ddns-server.wantedBy == [ ];
            message = "single-active units must not start at boot.";
          }
          {
            assertion = svc.kea-dhcp4-server.wantedBy != [ ];
            message = "D2 ownership must leave kea-dhcp4-server alone.";
          }
          {
            assertion = lib.hasInfix "notify_master" config.services.keepalived.vrrpInstances.main.extraConfig;
            message = "owned units need the keepalived notify hooks.";
          }
          {
            assertion = config.warnings == [ ] || lib.all (w: !(lib.hasInfix "singleActiveUnits" w)) config.warnings;
            message = "typed ownership must not warn about hand-listed units.";
          }
        ]
      );

  router-ha-ra-unset-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ra-unset" (pair { });

  router-ha-ra-unknown-network-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ra-unknown-network" (pair {
    ha.routerAdvertisements = {
      mode = "vrrp-owner";
      networks = [ "20-router-lna" ];
    };
  });

  router-ha-vrrp-network-mismatch-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-vrrp-network-mismatch" (pair {
    ha = raOwner // { vrrpNetwork = "20-router-lna"; };
  });

  router-ha-ra-owner-needs-vrrp-network-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ra-owner-needs-vrrp-network" (pair {
    ha = raOwner // { vrrpNetwork = null; };
  });

  router-ha-ra-silent-network-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ra-silent-network" (
    pair {
      ha.routerAdvertisements = {
        mode = "vrrp-owner";
        networks = [ "20-router-lan" ];
      };
    }
    ++ [ { services.router-networking.routedInterfaces.lan.ipv6SendRA = false; } ]
  );

  router-ha-ra-both-nodes-eval = check "router-ha-ra-both-nodes" (pair {
    ha.routerAdvertisements.mode = "both-nodes";
  }) (config: [
    {
      assertion = config.systemd.network.networks."20-router-lan".networkConfig.IPv6SendRA == true;
      message = "both-nodes must leave RAs as configured.";
    }
    {
      assertion = !(config.systemd.services ? router-ha-ra-owner);
      message = "both-nodes must not add the RA owner unit.";
    }
  ]);

  router-ha-ddns-unowned-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ddns-unowned" (pair {
    ha = raOwner;
    extra = ddns;
  });

  router-ha-ddns-manual-units-eval = check "router-ha-ddns-manual-units" (pair {
    ha = raOwner // {
      singleActiveUnits = [
        "inadyn.service"
        "inadyn.timer"
      ];
    };
    extra = ddns;
  }) (config: [
    {
      assertion = lib.any (lib.hasInfix "router-ddns.ha.singleActiveOwner") config.warnings;
      message = "hand-listed inadyn units should still evaluate, with a migration warning.";
    }
  ]);

  router-ha-ddns-service-only-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-ddns-service-only" (pair {
    # The old documented pattern: without the timer the backup keeps updating.
    ha = raOwner // { singleActiveUnits = [ "inadyn.service" ]; };
    extra = ddns;
  });

  router-ddns-owner-without-ha-fails-eval = eval.mkNixosEvalFailureCheck "router-ddns-owner-without-ha" [
    self.nixosModules.router-ha
    self.nixosModules.router-ddns
    (lib.recursiveUpdate ddns { services.router-ddns.ha.singleActiveOwner = true; })
  ];

  router-ha-upnp-unowned-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-upnp-unowned" (pair {
    ha = raOwner;
    extra = upnp;
  });

  router-ha-kea-d2-unowned-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-kea-d2-unowned" (pair {
    ha = raOwner;
    extra = kea { };
  });

  router-ha-kea-d2-follow-vip-eval = check "router-ha-kea-d2-follow-vip" (pair {
    ha = raOwner;
    extra = lib.recursiveUpdate (kea { ha.mode = "follow-vip"; }) keaHa;
  }) (config: [
    {
      assertion = config.services.router-kea.ddns.serverAddress == "10.10.10.1";
      message = "follow-vip must send D2 updates to the VIP address.";
    }
    {
      assertion = config.systemd.services.kea-dhcp-ddns-server.wantedBy != [ ];
      message = "follow-vip must run D2 on both nodes.";
    }
    {
      assertion = !(lib.elem "kea-dhcp-ddns-server.service" config.services.router-ha.singleActiveUnits);
      message = "follow-vip must not make D2 single-active.";
    }
  ]);

  router-ha-kea-ha-d2-single-active-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-kea-ha-d2-single-active" (pair {
    ha = raOwner;
    extra = lib.recursiveUpdate (kea { ha.mode = "single-active"; }) keaHa;
  });

  router-ha-kea-d2-follow-vip-loopback-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-kea-d2-follow-vip-loopback" (pair {
    ha = raOwner;
    extra = kea {
      ha.mode = "follow-vip";
      serverAddress = "127.0.0.1";
    };
  });
}
