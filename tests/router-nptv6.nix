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
          {
            internalPrefix = "fd00:2::/64";
            externalInterface = "tailscale0";
            autoDetect = true;
          }
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "snat to 2001:db8:1::/64" config.services.router-firewall.extraIpv6NatRules;
        message = "router-nptv6 should add static SNAT rule.";
      }
      {
        assertion = !lib.hasInfix "fd00:2::/64" config.services.router-firewall.extraIpv6NatRules;
        message = "router-nptv6 should NOT add autoDetect rules to static firewall string.";
      }
      {
        assertion = config.systemd.services ? router-nptv6-watch;
        message = "router-nptv6 should enable watch service when autoDetect is used.";
      }
      {
        assertion = lib.elem "VAGLIO_NPT_EXTERNAL_INTERFACES=tailscale0" config.systemd.services.router-nptv6-watch.serviceConfig.Environment;
        message = "router-nptv6-watch should have VAGLIO_NPT_EXTERNAL_INTERFACES=tailscale0 in Environment.";
      }
    ])
  ];
}
