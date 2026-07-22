{ lib, ... }:

{
  imports = [
    ../modules/runtime-compat.nix
  ];

  boot.isContainer = true;
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
}
