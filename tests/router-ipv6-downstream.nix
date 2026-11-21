{
  self,
  lib,
  eval,
}:

# Per-segment IPv6 from the ISP delegation: subnet IDs, the managed-flag
# warning, and the static prefix section (docs/router-ipv6-downstream.md).
let
  base = routed: [
    self.nixosModules.router-networking
    {
      services.router-networking = {
        enable = true;
        wan.device = "wan0";
        routedInterfaces = lib.recursiveUpdate {
          lan = {
            device = "lan0";
            ipv4Address = "10.0.10.1/24";
          };
          iot = {
            device = "lan1";
            ipv4Address = "10.0.20.1/24";
          };
        } routed;
      };
    }
  ];
  check = name: modules: assertions: eval.mkNixosEvalCheck name (modules ++ [ ({ config, ... }: { assertions = assertions config; }) ]);
in
{
  router-ipv6-downstream-eval = check "router-ipv6-downstream" (base {
    lan.ipv6SubnetId = "0x1";
    iot = {
      ipv6SubnetId = "20";
      prefixDelegationMode = "managed";
      ipv6Prefix = "2001:db8:ff::/64";
    };
  }) (config:
    let
      nets = config.systemd.network.networks;
    in
    [
      {
        assertion = nets."20-router-lan".dhcpPrefixDelegationConfig.SubnetId == "0x1"
          && nets."20-router-iot".dhcpPrefixDelegationConfig.SubnetId == "20";
        message = "ipv6SubnetId must render [DHCPPrefixDelegation] SubnetId=.";
      }
      {
        assertion = nets."20-router-lan".ipv6Prefixes == [ ];
        message = "the null default prefix must not render an [IPv6Prefix] section.";
      }
      {
        assertion = map (p: p.Prefix) nets."20-router-iot".ipv6Prefixes == [ "2001:db8:ff::/64" ];
        message = "a static ipv6Prefix must still render.";
      }
      {
        assertion = lib.any (w: lib.hasInfix "routedInterfaces.iot.prefixDelegationMode" w) config.warnings
          && !(lib.any (w: lib.hasInfix "routedInterfaces.lan.prefixDelegationMode" w) config.warnings);
        message = "managed mode must warn for that segment only.";
      }
    ]);

  router-ipv6-subnet-id-duplicate-fails-eval = eval.mkNixosEvalFailureCheck "router-ipv6-subnet-id-duplicate" (base {
    lan.ipv6SubnetId = "0x1";
    iot.ipv6SubnetId = "01";
  });

  router-ipv6-subnet-id-mixed-fails-eval = eval.mkNixosEvalFailureCheck "router-ipv6-subnet-id-mixed" (base {
    lan.ipv6SubnetId = "0x1";
  });

  router-ipv6-subnet-id-mixed-no-pd-eval = check "router-ipv6-subnet-id-mixed-no-pd" (base {
    lan.ipv6SubnetId = "0x1";
    iot.dhcpPrefixDelegation = false;
  }) (config: [
    {
      assertion = config.systemd.network.networks."20-router-lan".dhcpPrefixDelegationConfig.SubnetId == "0x1";
      message = "a segment without delegation does not need a subnet ID.";
    }
  ]);

  router-ipv6-subnet-id-invalid-fails-eval = eval.mkNixosEvalFailureCheck "router-ipv6-subnet-id-invalid" (base {
    lan.ipv6SubnetId = "lan";
  });
}
