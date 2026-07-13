{
  services.router-networking = {
    enable = true;
    wan.device = "wan0";
    routedInterfaces.lan = {
      device = "lan0";
      ipv4Address = "192.168.50.1/24";
      dns = [ "192.168.50.1" ];
      requiredForOnline = "routable";
    };
  };

  services.router-dhcp.enable = true;

  services.router-dns-service = {
    enable = true;
    provider = "unbound";
    searchDomains = [ "home.arpa" ];
    serviceListenAddresses = [
      "127.0.0.1"
      "192.168.50.1"
    ];
  };

  services.router-firewall.enable = true;

  services.router-optimizations = {
    enable = true;
    interfaces = {
      wan = {
        device = "wan0";
        role = "wan";
        label = "WAN";
        bandwidth = "1Gbit";
      };
      lan = {
        device = "lan0";
        role = "lan";
        label = "LAN";
      };
    };
  };
}
