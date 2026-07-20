{
  name = "ha-basic";
  backend = "systemd-nspawn";
  description = ''
    Minimal two-router HA lab for safe control-plane drills. This topology keeps
    DHCP in the current repo support posture: explicit single-active/manual
    promotion only.
  '';

  networks = {
    lan = {
      bridgeName = "lab-ha-lan";
      subnet = "192.0.2.0/24";
      vip = "192.0.2.1/24";
    };

    wan = {
      bridgeName = "lab-ha-wan";
      subnet = "198.51.100.0/24";
      upstream = "198.51.100.1/24";
    };
  };

  nodes = {
    router = {
      machine = "lab-ha-router";
      module = ../../machines/router.nix;
      lanAddress = "192.0.2.2/24";
      wanAddress = "198.51.100.2/24";
      vrrpRole = "master";
      priority = 110;
      singleActiveUnits = [ "router-lab-owner-demo.service" ];
    };

    router-backup = {
      machine = "lab-ha-router-backup";
      module = ../../machines/router-backup.nix;
      lanAddress = "192.0.2.3/24";
      wanAddress = "198.51.100.3/24";
      vrrpRole = "backup";
      priority = 90;
      singleActiveUnits = [ "router-lab-owner-demo.service" ];
    };

    wan = {
      machine = "lab-ha-wan";
      module = ../../machines/wan.nix;
      address = "198.51.100.1/24";
    };

    client = {
      machine = "lab-ha-client";
      module = ../../machines/client.nix;
      address = "192.0.2.50/24";
      defaultGateway = "192.0.2.1";
    };
  };

  scenarios = {
    vipSingleOwner = ../../scenarios/assert-vip-single-owner.sh;
    singleActiveDemoUnit = ../../scenarios/assert-single-active-demo-unit.sh;
  };

  supportBoundary = {
    automaticDhcpFailover = false;
    boundedSingleActiveService = "router-lab-owner-demo.service";
  };
}
