{
  self,
  lib,
  eval,
}:

let
  assertModule = assertions: { inherit assertions; };
in
{
  router-ipv6-multiwan-vpnexit-precedence-eval = eval.mkNixosEvalCheck "router-ipv6-multiwan-vpnexit-precedence" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        wans.backup.device = "wan1";
        routedInterfaces.lan = {
          device = "lan0";
          ipv4Address = "10.10.10.1/24";
          vpnExit = "wg0";
          policyRouting = {
            enable = true;
            table = 123;
            rules = [
              {
                to = "2001:db8:feed::/48";
                table = 123;
                priority = 110;
              }
            ];
          };
        };
      };
    }
    ({ config, ... }:
      let
        rules = config.systemd.network.networks."20-router-lan".routingPolicyRules;
        hasVpnExitRule = builtins.any (r: (r.Table or null) == 200 && (r.Priority or null) == 50) rules;
        hasInterfacePolicyRule = builtins.any (r: (r.Table or null) == 123 && (r.Priority or null) == 100) rules;
        hasDestinationPolicyRule = builtins.any (
          r:
          (r.Table or null) == 123
          && (r.Priority or null) == 110
          && (r.To or null) == "2001:db8:feed::/48"
        ) rules;
      in
      assertModule [
        {
          assertion = hasVpnExitRule;
          message = "router-networking should emit the reserved vpnExit rule on table 200 with higher precedence.";
        }
        {
          assertion = hasInterfacePolicyRule;
          message = "router-networking should preserve the interface policy-routing table rule.";
        }
        {
          assertion = hasDestinationPolicyRule;
          message = "router-networking should preserve explicit destination-based IPv6 policy-routing rules.";
        }
      ])
  ];

  router-ipv6-multiwan-masquerade-without-vpnexit-fails = eval.mkNixosEvalFailureCheck "router-ipv6-multiwan-masquerade-without-vpnexit" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        wans.backup.device = "wan1";
        routedInterfaces.lan = {
          device = "lan0";
          ipv4Address = "10.10.10.1/24";
          ipv6Masquerade = true;
        };
      };
    }
  ];

  router-ipv6-multiwan-pvd-steered-warning-eval = eval.mkNixosEvalCheck "router-ipv6-multiwan-pvd-steered-warning" [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        routedInterfaces.lan = {
          device = "lan0";
          ipv4Address = "10.10.10.1/24";
          vpnExit = "wg0";
          pvds = [
            {
              identifier = "isp.example.com";
              hFlag = false;
            }
          ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = builtins.any (w: lib.hasInfix "advanced/manual IPv6 multi-WAN shape" w) config.warnings;
        message = "router-networking should warn when PvD/native multi-prefix signalling is mixed with steered IPv6 egress.";
      }
    ])
  ];

  router-ipv6-multiwan-nptv6-explicit-uplink-eval = eval.mkNixosEvalCheck "router-ipv6-multiwan-nptv6-explicit-uplink" [
    self.nixosModules.router-networking
    self.nixosModules.router-firewall
    self.nixosModules.router-nptv6
    {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        wans.backup.device = "wan1";
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" "wan1" ];
        lanInterfaces = [ "lan0" ];
      };

      services.router-nptv6 = {
        enable = true;
        rules = [
          {
            internalPrefix = "fd00:10:20::/64";
            externalInterface = "wan1";
            externalPrefix = "2001:db8:2::/64";
          }
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "oifname \"wan1\"" config.services.router-firewall.extraIpv6NatRules;
        message = "router-nptv6 should preserve an explicit external uplink when used in a multi-WAN router.";
      }
    ])
  ];
}
