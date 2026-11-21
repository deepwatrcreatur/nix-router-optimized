{
  self,
  lib,
  eval,
}:

# router-ipsec: rendered XFRM netdev, swanctl connection, secrets handling,
# firewall rules, zone placement, BGP port, and invalid tunnels.
let
  base = extra: [
    self.nixosModules.router-firewall
    self.nixosModules.router-zones
    self.nixosModules.router-bgp
    self.nixosModules.router-ipsec
    (lib.recursiveUpdate {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
        lanInterfaces = [ "lan0" ];
      };
      services.router-zones = {
        enable = true;
        zones = {
          lan.interfaces = [ "lan0" ];
          vpn = { };
        };
      };
      services.router-ipsec = {
        enable = true;
        tunnels.branch = {
          ifId = 10;
          address = "169.254.10.1/30";
          remote.address = "203.0.113.20";
          pskFile = "/run/agenix/ipsec-branch";
          zone = "vpn";
          routes = [ "10.20.0.0/16" ];
          remotePrefixes = [ "10.30.0.0/16" ];
        };
      };
    } extra)
  ];
  check = name: modules: assertions: eval.mkNixosEvalCheck name (modules ++ [ ({ config, ... }: { assertions = assertions config; }) ]);
in
{
  router-ipsec-eval = check "router-ipsec" (base {
    services.router-bgp = {
      enable = true;
      asn = 65001;
      neighbors."169.254.10.2".remoteAs = 65002;
    };
  }) (config:
    let
      conn = config.services.strongswan-swanctl.swanctl.connections.branch;
      child = conn.children.branch;
      netdev = config.systemd.network.netdevs."40-xfrm-branch";
      net = config.systemd.network.networks."40-xfrm-branch";
      rules = config.services.router-firewall.extraInputEarlyRules;
    in
    [
      {
        assertion = netdev.netdevConfig.Kind == "xfrm" && netdev.xfrmConfig.InterfaceId == 10 && netdev.xfrmConfig.Independent;
        message = "the tunnel needs an independent XFRM netdev with its if_id.";
      }
      {
        assertion = net.address == [ "169.254.10.1/30" ]
          && lib.elem { Destination = "10.20.0.0/16"; } net.routes
          && lib.elem { Destination = "10.30.0.0/16"; Type = "blackhole"; Metric = 4000; } net.routes;
        message = "the tunnel network must carry its address, static routes and remote-prefix blackholes.";
      }
      {
        assertion = config.systemd.network.enable && child.dpd_action == "restart";
        message = "router-ipsec must enable networkd for its XFRM units; initiators restart on DPD.";
      }
      {
        assertion = child.if_id_in == "10" && child.if_id_out == "10" && child.local_ts == [ "0.0.0.0/0" ] && child.start_action == "trap|start";
        message = "the child SA must bind to the if_id with any-to-any selectors and retry on traffic.";
      }
      {
        assertion = conn.remote.main.auth == "psk" && conn.remote.main.id == "203.0.113.20";
        message = "the peer authenticates by PSK with its address as identity by default.";
      }
      {
        assertion = lib.elem "/run/router-ipsec/secrets.conf" config.services.strongswan-swanctl.includes
          && !(lib.hasInfix "ipsec-branch" (builtins.toJSON config.services.strongswan-swanctl.swanctl));
        message = "the PSK must come from the runtime include, never the swanctl config.";
      }
      {
        assertion = lib.hasInfix ''iifname { "wan0" } ip saddr 203.0.113.20 udp dport { 500, 4500 } accept'' rules
          && lib.hasInfix ''iifname { "wan0" } ip saddr 203.0.113.20 meta l4proto esp accept'' rules;
        message = "IKE and ESP must be admitted only on the WAN from the peer.";
      }
      {
        assertion = lib.hasInfix ''iifname "xfrm-branch" tcp dport { 179 } accept'' rules;
        message = "BGP must be reachable through the tunnel when a neighbor sits inside it.";
      }
      {
        assertion = config.services.router-zones.zones.vpn.interfaces == [ "xfrm-branch" ];
        message = "the tunnel interface must join its router-zones zone.";
      }
    ]);

  router-ipsec-no-bgp-port-eval = check "router-ipsec-no-bgp-port" (base { }) (config: [
    {
      assertion = !(lib.hasInfix "xfrm-branch" config.services.router-firewall.extraInputEarlyRules);
      message = "without a BGP neighbor in the tunnel no input port opens on it.";
    }
  ]);

  router-ipsec-responder-eval = check "router-ipsec-responder" (base {
    services.router-ipsec.tunnels.branch.initiate = false;
  }) (config: [
    {
      assertion = config.services.strongswan-swanctl.swanctl.connections.branch.children.branch.dpd_action == "clear";
      message = "a responder-only tunnel must not re-initiate on DPD.";
    }
  ]);

  router-ipsec-default-bundle-eval = check "router-ipsec-default-bundle" [
    self.nixosModules.default
    {
      services.router-firewall.wanInterfaces = [ "wan0" ];
      services.router-ipsec = {
        enable = true;
        tunnels.branch = {
          ifId = 10;
          address = "169.254.10.1/30";
          remote.address = "203.0.113.20";
          pskFile = "/run/agenix/ipsec-branch";
        };
      };
    }
  ] (config: [
    {
      assertion = config.systemd.network.netdevs ? "40-xfrm-branch";
      message = "router-ipsec must be usable from the default bundle.";
    }
  ]);

  router-ipsec-duplicate-interface-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-duplicate-interface" (base {
    services.router-ipsec.tunnels.other = {
      ifId = 11;
      interface = "xfrm-branch";
      address = "169.254.11.1/30";
      remote.address = "203.0.113.30";
      pskFile = "/run/agenix/ipsec-other";
    };
  });

  router-ipsec-peer-in-routes-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-peer-in-routes" (base {
    services.router-ipsec.tunnels.branch.routes = [ "0.0.0.0/0" ];
  });

  router-ipsec-no-wan-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-no-wan" (base {
    services.router-firewall.wanInterfaces = lib.mkForce [ ];
  });

  router-ipsec-unknown-zone-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-unknown-zone" (base {
    services.router-ipsec.tunnels.branch.zone = "vnp";
  });

  router-ipsec-long-interface-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-long-interface" (base {
    services.router-ipsec.tunnels.branch.interface = "xfrm-very-long-name";
  });

  router-ipsec-store-psk-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-store-psk" (base {
    services.router-ipsec.tunnels.branch.pskFile = "/nix/store/abc-psk";
  });

  router-ipsec-duplicate-ifid-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-duplicate-ifid" (base {
    services.router-ipsec.tunnels.other = {
      ifId = 10;
      address = "169.254.11.1/30";
      remote.address = "203.0.113.30";
      pskFile = "/run/agenix/ipsec-other";
    };
  });

  router-ipsec-any-initiator-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-any-initiator" (base {
    services.router-ipsec.tunnels.branch.remote.address = "%any";
  });

  router-ipsec-flowtable-fails-eval = eval.mkNixosEvalFailureCheck "router-ipsec-flowtable" (base {
    services.router-firewall.flowtable = {
      enable = true;
      interfaces = [ "wan0" "lan0" "xfrm-branch" ];
    };
  });
}
