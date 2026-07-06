{
  self,
  lib,
  eval,
}:

let
  assertModule = assertions: { inherit assertions; };

  optimizationInterfaces = {
    services.router-optimizations = {
      enable = true;
      interfaces = {
        wan = {
          device = "eth-wan";
          role = "wan";
          label = "WAN";
        };
        lan = {
          device = "br-lan";
          role = "lan";
          label = "LAN";
        };
        mgmt = {
          device = "mgmt0";
          role = "management";
          label = "Management";
        };
      };
    };
  };

  firewallWithoutWan = {
    services.router-firewall = {
      enable = true;
      autoInterfacesFromOptimizations = false;
    };
  };
in
{
  router-firewall-derives-interfaces-eval = eval.mkNixosEvalCheck "router-firewall-derives-interfaces" [
    self.nixosModules.router-optimizations
    self.nixosModules.router-firewall
    optimizationInterfaces
    {
      services.router-firewall.enable = true;
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix ''iifname {"br-lan"} oifname {"eth-wan"} accept'' config.networking.nftables.ruleset;
        message = "router-firewall should derive LAN-to-WAN forwarding from router-optimizations.";
      }
      {
        assertion = lib.hasInfix ''iifname {"mgmt0"} oifname {"eth-wan"} accept'' config.networking.nftables.ruleset;
        message = "router-firewall should derive management-to-WAN forwarding from router-optimizations.";
      }
      {
        assertion = lib.hasInfix ''iifname {"eth-wan"} jump WAN_LOCAL'' config.networking.nftables.ruleset;
        message = "router-firewall should derive WAN input dispatch from router-optimizations.";
      }
    ])
  ];

  router-firewall-extra-trusted-only-eval = eval.mkNixosEvalCheck "router-firewall-extra-trusted-only" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth-wan" ];
        extraTrustedInterfaces = [ "wg0" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = !(lib.hasInfix "iifname  " config.networking.nftables.ruleset);
        message = "router-firewall should not render empty iifname matches when only extra trusted interfaces are configured.";
      }
      {
        assertion = !(lib.hasInfix "oifname  " config.networking.nftables.ruleset);
        message = "router-firewall should not render empty oifname matches when only extra trusted interfaces are configured.";
      }
    ])
  ];

  router-firewall-flowtable-filters-missing-interfaces-eval = eval.mkNixosEvalCheck "router-firewall-flowtable-filters-missing-interfaces" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth-wan" ];
        lanInterfaces = [
          "br-lan"
          "br-lan.20"
        ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion =
          lib.hasInfix "/sys/class/net/$iface" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should filter interfaces against /sys/class/net.";
      }
      {
        assertion =
          lib.hasInfix "skipping missing interfaces" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should report skipped interfaces.";
      }
      {
        assertion =
          lib.hasInfix "no flowtable interfaces are present; skipping setup" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should exit cleanly when no configured interfaces exist.";
      }
      {
        assertion =
          lib.hasInfix "router-firewall-flowtable" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should tag module-managed flowtable rules distinctly.";
      }
      {
        assertion =
          lib.hasInfix "delete rule inet filter forward handle" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should delete only managed or exact legacy flowtable forward rules before inserting the current set.";
      }
      {
        assertion =
          lib.hasInfix "nft -f \"$transaction_file\"" config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should apply stale-rule deletion and insertion in a single nft transaction.";
      }
    ])
  ];

  router-firewall-flowtable-default-split-rules-eval = eval.mkNixosEvalCheck "router-firewall-flowtable-default-split-rules" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth-wan" ];
        lanInterfaces = [ "br-lan" ];
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion =
          lib.hasInfix "meta l4proto tcp flow add @f comment \"router-firewall-flowtable tcp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should offload TCP by default.";
      }
      {
        assertion =
          lib.hasInfix "meta l4proto udp flow add @f comment \"router-firewall-flowtable udp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should offload UDP by default.";
      }
    ])
  ];

  router-firewall-flowtable-explicit-exclusions-eval = eval.mkNixosEvalCheck "router-firewall-flowtable-explicit-exclusions" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth-wan" ];
        lanInterfaces = [ "br-lan" ];
        flowtable = {
          excludeTcpPorts = [
            5060
            5061
          ];
          excludeUdpPorts = [
            5060
            5061
            "10000-20000"
          ];
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion =
          lib.hasInfix "tcp dport != { 5060, 5061 } flow add @f comment \"router-firewall-flowtable tcp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should keep excluded TCP ports off the flowtable.";
      }
      {
        assertion =
          lib.hasInfix "udp dport != { 5060, 5061, 10000-20000 } flow add @f comment \"router-firewall-flowtable udp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall flowtable helper should keep excluded UDP ports and ranges off the flowtable.";
      }
    ])
  ];

  router-firewall-flowtable-sip-friendly-preset-eval = eval.mkNixosEvalCheck "router-firewall-flowtable-sip-friendly-preset" [
    self.nixosModules.router-firewall
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth-wan" ];
        lanInterfaces = [ "br-lan" ];
        flowtable.sipFriendly.enable = true;
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion =
          lib.hasInfix "tcp dport != { 5060, 5061 } flow add @f comment \"router-firewall-flowtable tcp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall sipFriendly preset should exclude common SIP TCP signaling ports from flowtable acceleration.";
      }
      {
        assertion =
          lib.hasInfix "udp dport != { 5060, 5061, 10000-20000 } flow add @f comment \"router-firewall-flowtable udp\""
            config.systemd.services.router-firewall-flowtable.script;
        message = "router-firewall sipFriendly preset should exclude common SIP/RTP UDP ports from flowtable acceleration.";
      }
    ])
  ];

  router-firewall-flowtable-invalid-range-fails-eval =
    eval.mkNixosEvalFailureCheck "router-firewall-flowtable-invalid-range" [
      self.nixosModules.router-firewall
      {
        services.router-firewall = {
          enable = true;
          wanInterfaces = [ "eth-wan" ];
          lanInterfaces = [ "br-lan" ];
          flowtable.excludeUdpPorts = [ "20000-10000" ];
        };
      }
    ];

  router-wireguard-route-to-derived-wan-eval = eval.mkNixosEvalCheck "router-wireguard-route-to-derived-wan" [
    self.nixosModules.router-optimizations
    self.nixosModules.router-firewall
    self.nixosModules.router-wireguard
    optimizationInterfaces
    {
      services = {
        router-firewall.enable = true;
        router-wireguard = {
          enable = true;
          privateKeyFile = "/run/secrets/wireguard-private-key";
          routeToWan = true;
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix ''iifname "wg0" oifname { "eth-wan" } accept'' config.services.router-firewall.extraForwardRules;
        message = "router-wireguard routeToWan should derive WAN interfaces from router-optimizations.";
      }
    ])
  ];

  router-openvpn-route-to-derived-wan-eval = eval.mkNixosEvalCheck "router-openvpn-route-to-derived-wan" [
    self.nixosModules.router-optimizations
    self.nixosModules.router-firewall
    self.nixosModules.router-openvpn
    optimizationInterfaces
    {
      services = {
        router-firewall.enable = true;
        router-openvpn.instances.roadwarrior = {
          interfaceName = "tun-roadwarrior";
          config = "dev tun-roadwarrior";
          routeToWan = true;
        };
      };
    }
    ({ config, ... }: assertModule [
      {
        assertion = lib.hasInfix ''iifname "tun-roadwarrior" oifname { "eth-wan" } accept'' config.services.router-firewall.extraForwardRules;
        message = "router-openvpn routeToWan should derive WAN interfaces from router-optimizations.";
      }
    ])
  ];

  router-openvpn-route-to-wan-no-wan-fails-eval =
    eval.mkNixosEvalFailureCheck "router-openvpn-route-to-wan-no-wan" [
      self.nixosModules.router-firewall
      self.nixosModules.router-openvpn
      firewallWithoutWan
      {
        services.router-openvpn.instances.roadwarrior = {
          interfaceName = "tun-roadwarrior";
          config = "dev tun-roadwarrior";
          routeToWan = true;
        };
      }
    ];
}
