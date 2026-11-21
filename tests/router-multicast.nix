{
  self,
  lib,
  eval,
}:

# router-multicast: rendered igmpproxy config, firewall rules and invalid
# interface layouts (docs/router-multicast.md).
let
  base = extra: [
    self.nixosModules.router-firewall
    self.nixosModules.router-multicast
    (lib.recursiveUpdate {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" "wan0.40" ];
        lanInterfaces = [ "lan0" "lan1" ];
      };
      services.router-multicast = {
        enable = true;
        upstream.interface = "wan0.40";
        downstreams = [ "lan0" ];
      };
    } extra)
  ];
  check = name: modules: assertions: eval.mkNixosEvalCheck name (modules ++ [ ({ config, ... }: { assertions = assertions config; }) ]);
in
{
  router-multicast-eval = check "router-multicast" (base {
    services.router-multicast = {
      upstream.allowGroups = [ "239.0.0.0/8" ];
      denyGroups = [ "239.255.255.250/32" ];
    };
  }) (config:
    let
      fw = config.services.router-firewall;
    in
    [
      {
        assertion = lib.hasInfix ''iifname "wan0.40" oifname { "lan0" } ip daddr 224.0.0.0/4 accept'' fw.extraForwardEarlyRules
          && !(lib.hasInfix "lan1" fw.extraForwardEarlyRules);
        message = "streams must be forwarded from the upstream to the listed downstreams only.";
      }
      {
        assertion = lib.hasInfix ''iifname { "wan0.40", "lan0" } ip protocol igmp accept'' fw.extraInputEarlyRules;
        message = "IGMP must be accepted on the upstream and downstreams.";
      }
      {
        assertion = lib.any (lib.hasInfix "router-multicast-rp-filter") config.systemd.services.router-multicast.serviceConfig.ExecStartPre;
        message = "the upstream rp_filter must be set loose by default.";
      }
    ]);

  router-multicast-strict-rp-eval = check "router-multicast-strict-rp" (base {
    services.router-multicast.looseReversePathFilter = false;
  }) (config: [
    {
      assertion = config.systemd.services.router-multicast.serviceConfig.ExecStartPre == [ ];
      message = "looseReversePathFilter = false must leave rp_filter alone.";
    }
  ]);

  router-multicast-upstream-downstream-fails-eval = eval.mkNixosEvalFailureCheck "router-multicast-upstream-downstream" (base {
    services.router-multicast.downstreams = [ "lan0" "wan0.40" ];
  });

  router-multicast-no-downstreams-fails-eval = eval.mkNixosEvalFailureCheck "router-multicast-no-downstreams" (base {
    services.router-multicast.downstreams = lib.mkForce [ ];
  });
}
