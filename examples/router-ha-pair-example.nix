let
  commonModule = {
    services.router-ha = {
      enable = true;
      virtualIp = "10.10.10.1/24";
      vrrpInterface = "lan0";
      vrrpId = 51;
      # Read at runtime as a systemd credential; it never enters the Nix
      # store. Use the same file content on both nodes (agenix, sops-nix or
      # clan vars). Keepalived uses the first 8 characters.
      vrrpPasswordFile = "/run/secrets/router-vrrp-password";
      wan = {
        enable = true;
        interface = "wan0";
        clonedMac = "02:00:00:00:00:01";
        # The .network below gets ActivationPolicy=manual; only the VRRP
        # master brings wan0 up. Detected automatically when router-networking
        # manages the WAN.
        network = "10-wan";
      };
      singleActiveUnits = [
        "inadyn.service"
      ];
    };

    systemd.network.networks."10-wan" = {
      matchConfig.Name = "wan0";
      networkConfig.DHCP = "yes";
    };

    services.router-ntp = {
      enable = true;
      lanSubnets = [ "10.10.10.0/24" ];
    };

    services.router-firewall = {
      enable = true;
      wanInterfaces = [ "wan0" ];
      lanInterfaces = [ "lan0" ];
    };
  };
in
{
  common = commonModule;

  master = {
    imports = [ commonModule ];

    services.router-ha = {
      role = "master";
      priority = 100;
    };
  };

  backup = {
    imports = [ commonModule ];

    services.router-ha = {
      role = "backup";
      priority = 90;
    };
  };
}
