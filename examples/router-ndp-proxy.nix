{ inputs, ... }:

{
  imports = [
    inputs.router-optimized.nixosModules.router-ndp-proxy
  ];

  services.router-ndp-proxy = {
    enable = true;
    upstreamInterface = "eth0";
    downstreamInterfaces = [ "br-lan" ];

    prefixes = [
      {
        prefix = "2001:db8:100::/64";
        method = "interface";
        downstreamInterface = "br-lan";
      }
      {
        prefix = "2001:db8:101::/64";
        method = "auto";
      }
    ];
  };
}
