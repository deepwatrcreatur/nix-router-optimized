{
  self,
  lib,
  eval,
}:

# router-dhcp-relay: rendered networkd relay settings, firewall rules, the
# interaction with Kea/router-dhcp auto-detection, and invalid configs.
let
  base = extra: [
    self.nixosModules.router-networking
    self.nixosModules.router-firewall
    self.nixosModules.router-dhcp
    self.nixosModules.router-kea
    self.nixosModules.router-dhcp-relay
    (lib.recursiveUpdate {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        routedInterfaces = {
          office = {
            device = "lan1";
            ipv4Address = "10.20.0.1/24";
          };
          lan = {
            device = "lan0";
            ipv4Address = "10.10.10.1/24";
          };
        };
      };
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
        lanInterfaces = [
          "lan0"
          "lan1"
        ];
      };
      services.router-dhcp-relay = {
        enable = true;
        interfaces.office.server = "10.10.10.5";
      };
    } extra)
  ];

  check = name: modules: assertions: eval.mkNixosEvalCheck name (modules ++ [ ({ config, ... }: { assertions = assertions config; }) ]);
in
{
  router-dhcp-relay-eval =
    check "router-dhcp-relay"
      (base {
        services.router-dhcp-relay.interfaces.office.remoteId = "branch";
        services.router-dhcp.enable = true;
        services.router-kea = {
          enable = true;
          dhcp4 = {
            subnet = "10.10.10.0/24";
            gatewayAddress = "10.10.10.1";
            poolRanges = [
              {
                start = "10.10.10.100";
                end = "10.10.10.199";
              }
            ];
          };
        };
      })
      (
        config:
        let
          office = config.systemd.network.networks."20-router-office";
          rules = config.services.router-firewall.extraInputRules;
        in
        [
          {
            assertion =
              office.networkConfig.DHCPServer == true
              && office.dhcpServerConfig.RelayTarget == "10.10.10.5"
              && office.dhcpServerConfig.RelayAgentCircuitId == "string:lan1"
              && office.dhcpServerConfig.RelayAgentRemoteId == "string:branch";
            message = "the relayed segment must render RelayTarget and both option-82 suboptions.";
          }
          {
            assertion = !(office.dhcpServerConfig ? PoolOffset);
            message = "router-dhcp auto-detection must skip relayed segments.";
          }
          {
            assertion = config.services.kea.dhcp4.settings.interfaces-config.interfaces == [ "lan0" ];
            message = "router-kea auto-detection must skip relayed segments.";
          }
          {
            assertion =
              lib.hasInfix ''iifname { "lan1" } udp dport 67 accept'' rules
              && lib.hasInfix "ip saddr 10.10.10.5 udp sport 67 udp dport 67 fib saddr . iif oif exists accept" rules;
            message = "the firewall must admit relay clients and the server's replies.";
          }
        ]
      );

  router-dhcp-relay-no-circuit-id-eval = check "router-dhcp-relay-no-circuit-id" (base {
    services.router-dhcp-relay.interfaces.office = {
      circuitId = null;
      remoteId = "branch";
    };
  }) (config: [
    {
      assertion = !(config.systemd.network.networks."20-router-office".dhcpServerConfig ? RelayAgentCircuitId);
      message = "circuitId = null must omit the suboption.";
    }
  ]);

  router-dhcp-relay-chained-eval = check "router-dhcp-relay-chained" (base {
    # Next hop is another relay; the DHCP server answers this relay directly.
    services.router-dhcp-relay.interfaces.office = {
      server = "10.10.10.6";
      replyFrom = [ "10.99.0.5" ];
    };
    services.router-dhcp = {
      enable = true;
      interfaces.office.enable = false;
    };
  }) (config: [
    {
      assertion = lib.hasInfix "ip saddr 10.99.0.5 udp sport 67" config.services.router-firewall.extraInputRules
        && !(lib.hasInfix "ip saddr 10.10.10.6" config.services.router-firewall.extraInputRules);
      message = "replyFrom must replace the server in the reply rule.";
    }
  ]);

  router-dhcp-relay-null-server-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-null-server" (base {
    services.router-dhcp-relay.interfaces.office.server = "0.0.0.0";
  });

  router-dhcp-relay-bad-octet-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-bad-octet" (base {
    services.router-dhcp-relay.interfaces.office.server = "10.10.10.300";
  });

  router-dhcp-relay-no-ids-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-no-ids" (base {
    services.router-dhcp-relay.interfaces.office.circuitId = null;
  });

  router-dhcp-relay-kea-wildcard-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-kea-wildcard" (base {
    services.kea.dhcp4 = {
      enable = true;
      settings.interfaces-config.interfaces = [ "*" ];
    };
  });

  router-dhcp-relay-unknown-interface-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-unknown-interface" (base {
    services.router-dhcp-relay.interfaces.ofice.server = "10.10.10.5";
  });

  router-dhcp-relay-ipv6-server-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-ipv6-server" (base {
    services.router-dhcp-relay.interfaces.office.server = "fd00::5";
  });

  router-dhcp-relay-router-dhcp-conflict-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-router-dhcp-conflict" (base {
    services.router-dhcp = {
      enable = true;
      interfaces.office = { };
    };
  });

  router-dhcp-relay-kea-conflict-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-relay-kea-conflict" (base {
    services.router-kea = {
      enable = true;
      dhcp4 = {
        interfaces = [
          "lan0"
          "lan1"
        ];
        subnet = "10.10.10.0/24";
        gatewayAddress = "10.10.10.1";
        poolRanges = [
          {
            start = "10.10.10.100";
            end = "10.10.10.199";
          }
        ];
      };
    };
  });
}
