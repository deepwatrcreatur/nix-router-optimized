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
