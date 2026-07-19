{ ... }:

{
  boot.isContainer = true;
  networking.hostName = "lab-ha-wan";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.useHostResolvConf = false;
  services.resolved.enable = false;

  system.stateVersion = "25.11";

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
  };

  environment.etc."resolv.conf".text = ''
    nameserver 1.1.1.1
  '';

  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "host0";
    address = [ "198.51.100.1/24" ];
  };
}
