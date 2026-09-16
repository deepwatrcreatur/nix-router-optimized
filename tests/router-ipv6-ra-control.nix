{
  self,
  lib,
  eval,
}:

let
  networkingBase = {
    services.router-networking = {
      enable = true;
      wan = {
        device = "wan0";
      };
      routedInterfaces.lan0 = {
        device = "lan0";
        ipv4Address = "10.10.10.1/24";
        ipv6SendRA = false;
        dhcpPrefixDelegation = false;
      };
      routedInterfaces.lan1 = {
        device = "lan1";
        ipv4Address = "10.10.20.1/24";
        ipv6SendRA = true;
        routerLifetimeSec = 0;
      };
    };
  };

  assertModule = assertions: { inherit assertions; };
in
{
  router-ipv6-ra-control-eval = eval.mkNixosEvalCheck "router-ipv6-ra-control" [
    self.nixosModules.router-networking
    networkingBase
    ({ config, ... }: assertModule [
      {
        assertion = config.systemd.network.networks."20-router-lan0".networkConfig.IPv6SendRA == false;
        message = "router-networking should allow setting IPv6SendRA = false on routed interfaces.";
      }
      {
        assertion = config.systemd.network.networks."20-router-lan0".networkConfig.DHCPPrefixDelegation == false;
        message = "router-networking should allow setting DHCPPrefixDelegation = false on routed interfaces.";
      }
      {
        assertion = config.systemd.network.networks."20-router-lan1".networkConfig.IPv6SendRA == true;
        message = "router-networking should allow setting IPv6SendRA = true on routed interfaces.";
      }
      {
        assertion = config.systemd.network.networks."20-router-lan1".ipv6SendRAConfig.RouterLifetimeSec == 0;
        message = "router-networking should set RouterLifetimeSec in ipv6SendRAConfig when specified.";
      }
    ])
  ];
}
