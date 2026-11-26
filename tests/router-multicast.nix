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
        assertion = lib.hasInfix ''iifname { "lan0" } ip protocol igmp accept'' fw.extraInputEarlyRules
          && lib.hasInfix ''iifname "wan0.40" igmp type membership-query accept'' fw.extraInputEarlyRules
          && !(lib.hasInfix ''"wan0.40" } ip protocol igmp'' fw.extraInputEarlyRules);
        message = "downstreams accept all IGMP; the upstream only membership queries.";
      }
      {
        assertion = lib.any (lib.hasInfix "router-multicast-rp-filter") config.systemd.services.router-multicast.serviceConfig.ExecStartPre;
        message = "the upstream rp_filter must be set loose by default.";
      }
    ]);

  router-multicast-native-nftables-eval = check "router-multicast-native-nftables" [
    self.nixosModules.router-multicast
    {
      networking.nftables.enable = true;
      services.router-multicast = {
        enable = true;
        upstream.interface = "wan0.40";
        downstreams = [ "lan0" ];
      };
    }
  ] (config: [
    {
      assertion = lib.hasInfix "igmp type membership-query accept" config.networking.firewall.extraInputRules
        && lib.hasInfix ''iifname { "lan0" } ip protocol igmp accept'' config.networking.firewall.extraInputRules;
      message = "without router-firewall, the NixOS nftables firewall must admit IGMP.";
    }
  ]);

  router-multicast-native-iptables-eval = check "router-multicast-native-iptables" [
    self.nixosModules.router-multicast
    {
      services.router-multicast = {
        enable = true;
        upstream.interface = "wan0.40";
        downstreams = [ "lan0" ];
      };
    }
  ] (config: [
    {
      assertion = lib.hasInfix "-i lan0 -p igmp -j nixos-fw-accept" config.networking.firewall.extraCommands
        && lib.hasInfix "-i wan0.40 -p igmp -m u32" config.networking.firewall.extraCommands;
      message = "without router-firewall, the NixOS iptables firewall must admit IGMP.";
    }
  ]);

  router-multicast-default-bundle-eval = check "router-multicast-default-bundle" [
    self.nixosModules.default
    {
      services.router-multicast = {
        enable = true;
        upstream.interface = "wan0";
        downstreams = [ "lan0" ];
      };
    }
  ] (config: [
    {
      assertion = config.systemd.services ? router-multicast;
      message = "router-multicast must be usable from the default bundle.";
    }
  ]);

  router-multicast-strict-rp-eval = check "router-multicast-strict-rp" (base {
    services.router-multicast.looseReversePathFilter = false;
  }) (config: [
    {
      assertion = !(lib.any (lib.hasInfix "router-multicast-rp-filter") config.systemd.services.router-multicast.serviceConfig.ExecStartPre);
      message = "looseReversePathFilter = false must leave rp_filter alone.";
    }
  ]);

  # router-security-hardened zeroes per-interface rp_filter so `all` decides;
  # it must skip the upstream that igmpproxy deliberately sets to loose.
  router-multicast-with-hardened-rp-filter-eval = check "router-multicast-with-hardened-rp-filter" (base { } ++ [
    self.nixosModules.router-security-hardened
    {
      services.router-security-hardened = {
        enable = true;
        kernelHardening.enable = true;
      };
    }
  ]) (config: [
    {
      assertion = lib.hasInfix "| wan0.40)" config.systemd.services.router-rp-filter-reset.script;
      message = "router-rp-filter-reset must keep the multicast upstream's loose rp_filter.";
    }
  ]);

  router-multicast-upstream-downstream-fails-eval = eval.mkNixosEvalFailureCheck "router-multicast-upstream-downstream" (base {
    services.router-multicast.downstreams = [ "lan0" "wan0.40" ];
  });

  router-multicast-no-downstreams-fails-eval = eval.mkNixosEvalFailureCheck "router-multicast-no-downstreams" (base {
    services.router-multicast.downstreams = lib.mkForce [ ];
  });
}
