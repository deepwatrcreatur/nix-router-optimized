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
        pvds = [
          {
            identifier = "isp.example.com";
            hFlag = false;
            sequenceNumber = 1;
          }
          {
            identifier = "vpn.example.com";
            hFlag = true;
            sequenceNumber = 42;
          }
        ];
      };
    };
  };

  assertModule = assertions: { inherit assertions; };
in
{
  router-pvd-eval = eval.mkNixosEvalCheck "router-pvd" [
    self.nixosModules.router-networking
    networkingBase
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix "PvD=yes" config.systemd.network.networks."20-router-lan0".extraConfig;
        message = "router-networking should enable PvD in [IPv6SendRA] via extraConfig.";
      }
      {
        assertion = lib.hasInfix "Identifier=isp.example.com" config.systemd.network.networks."20-router-lan0".extraConfig;
        message = "router-networking should set first PvD Identifier.";
      }
      {
        assertion = lib.hasInfix "Identifier=vpn.example.com" config.systemd.network.networks."20-router-lan0".extraConfig;
        message = "router-networking should set second PvD Identifier.";
      }
      {
        assertion = lib.hasInfix "HFlag=yes" config.systemd.network.networks."20-router-lan0".extraConfig;
        message = "router-networking should set HFlag=yes for vpn PvD.";
      }
      {
        assertion = lib.hasInfix "SequenceNumber=42" config.systemd.network.networks."20-router-lan0".extraConfig;
        message = "router-networking should set SequenceNumber=42 for vpn PvD.";
      }
    ])
  ];
}
