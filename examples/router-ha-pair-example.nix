let
  commonModule = {
    services.router-ha = {
      enable = true;
      virtualIp = "10.10.10.1/24";
      vrrpInterface = "lan0";
      vrrpId = 51;
      # This value is rendered into store-backed Keepalived config. Do not
      # treat it like a high-value secret or commit a real shared password in a
      # public repository.
      vrrpPassword = "replace-me";
      wan = {
        enable = true;
        interface = "wan0";
        clonedMac = "02:00:00:00:00:01";
      };
      singleActiveUnits = [
        "inadyn.service"
      ];
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
