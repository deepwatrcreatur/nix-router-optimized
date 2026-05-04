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
  router-nptv6-eval = eval.mkNixosEvalCheck "router-nptv6" [
    self.nixosModules.router-firewall
    self.nixosModules.router-nptv6
    firewallBase
    {
      services.router-nptv6 = {
        enable = true;
        rules = [
          {
            internalPrefix = "fd00:1::/64";
            externalInterface = "wan0";
            externalPrefix = "2001:db8:1::/64";
          }
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "snat to 2001:db8:1::/64" config.services.router-firewall.extraIpv6NatRules;
        message = "router-nptv6 should add SNAT rule (stateful fallback).";
      }
      {
        assertion = lib.hasInfix "dnat to fd00:1::/64" config.services.router-firewall.extraIpv6PreroutingRules;
        message = "router-nptv6 should add DNAT rule (stateful fallback).";
      }
    ])
  ];
}
