{
  self,
  lib,
  eval,
}:

let
  networking = {
    services.router-networking = {
      enable = true;
      wan.device = "wan0";
      routedInterfaces.lan = {
        device = "lan0";
        ipv4Address = "10.10.10.4/16";
      };
    };
  };
  linkUrls = config: map (link: link.url) config.services.router-dashboard.links;
in
{
  router-homelab-wildcard-links-eval = eval.mkNixosEvalCheck "router-homelab-wildcard-links" [
    self.nixosModules.router-networking
    self.nixosModules.router-homelab
    networking
    { services.router-homelab = { enable = true; listenAddress = "0.0.0.0"; }; }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.elem "http://10.10.10.4:19999/" (linkUrls config)
            && !(lib.any (lib.hasInfix "0.0.0.0") (linkUrls config));
          message = "with a wildcard bind, dashboard links must use the routed LAN address.";
        }
      ];
    })
  ];

  router-homelab-link-address-eval = eval.mkNixosEvalCheck "router-homelab-link-address" [
    self.nixosModules.router-networking
    self.nixosModules.router-homelab
    networking
    {
      services.router-homelab = {
        enable = true;
        listenAddress = "0.0.0.0";
        linkAddress = "router.home.example";
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.elem "http://router.home.example:19999/" (linkUrls config);
          message = "linkAddress must override the dashboard link host.";
        }
      ];
    })
  ];

  router-homelab-ipv6-link-address-eval = eval.mkNixosEvalCheck "router-homelab-ipv6-link-address" [
    self.nixosModules.router-networking
    self.nixosModules.router-homelab
    networking
    {
      services.router-homelab = {
        enable = true;
        linkAddress = "fd12:3456::1";
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.elem "http://[fd12:3456::1]:19999/" (linkUrls config);
          message = "IPv6 link hosts must be bracketed in URLs.";
        }
      ];
    })
  ];
}
