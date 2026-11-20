{ ... }:

{
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

  systemd.network.enable = true;

  # Lab-only VRRP password on a lab-only bridge; real pairs decrypt this file
  # from a secret manager. Exercises the same credential path as production.
  environment.etc."router-ha/vrrp-password".text = "lab-only";
  services.router-ha.vrrpPasswordFile = "/etc/router-ha/vrrp-password";
}
