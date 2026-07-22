{ lib, ... }:

{
  imports = [
    ../modules/runtime-compat.nix
  ];

  boot.isContainer = true;
  networking.hostName = "lab-ha-client";
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

  users.users.messagebus.home = lib.mkForce "/var/empty";

  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "host0";
    address = [ "192.0.2.50/24" ];
    routes = [
      {
        Gateway = "192.0.2.1";
      }
    ];
  };
}
