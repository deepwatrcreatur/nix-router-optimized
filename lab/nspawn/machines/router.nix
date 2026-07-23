{ ... }:

{
  imports = [
    ./common-router.nix
    ../../../modules/router-ha.nix
    ../modules/router-lab-owner-demo-service.nix
  ];

  networking.hostName = "lab-ha-router";

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "host0";
    address = [ "192.0.2.2/24" ];
    networkConfig = {
      IPv6AcceptRA = false;
    };
  };

  systemd.network.networks."20-wan" = {
    matchConfig.Name = "host1";
    address = [ "198.51.100.2/24" ];
    routes = [
      {
        Gateway = "198.51.100.1";
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
    };
  };

  services.router-ha = {
    enable = true;
    role = "master";
    virtualIp = "192.0.2.1/24";
    vrrpInterface = "host0";
    priority = 110;
    singleActiveUnits = [ "router-lab-owner-demo.service" ];
  };

  services.keepalived.vrrpInstances.main = {
    # The nspawn lab uses unicast VRRP to avoid backend-specific multicast gaps.
    unicastSrcIp = "192.0.2.2";
    unicastPeers = [ "192.0.2.3" ];
  };

  services.keepalived.openFirewall = true;
}
