{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-networking
    inputs.router-optimized.nixosModules.router-firewall
    inputs.router-optimized.nixosModules.router-bgp
  ];

  services.router-networking = {
    enable = true;
    wan.device = "enp1s0";

    routedInterfaces = {
      lan = {
        device = "br-lan";
        ipv4Address = "10.10.20.1/24";
        dns = [ "10.10.20.1" ];
        requiredForOnline = "routable";
      };

      transit = {
        device = "enp2s0";
        ipv4Address = "10.10.254.1/30";
        requiredForOnline = "carrier";
      };
    };
  };

  services.router-firewall = {
    enable = true;
    wanInterfaces = [ "enp1s0" ];
    lanInterfaces = [ "br-lan" ];
    wanTcpPorts = [ 22 ];
    extraTrustedInterfaces = [ "enp2s0" ];
  };

  services.router-bgp = {
    enable = true;
    asn = 65001;
    routerId = "10.10.20.1";

    neighbors."10.10.254.2" = {
      remoteAs = 65010;
      description = "proxmox-frr";
      nextHopSelf = true;
    };

    networks = [
      "10.10.20.0/24"
      "10.10.30.0/24"
    ];
  };
}
