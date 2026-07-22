{ lib, ... }:

{
  # The phase-1 nspawn lab currently uses extracted LXC roots rather than the
  # host's regular container manager path. Force an explicit working directory
  # for the services that are currently failing with status=200/CHDIR so the
  # live rehearsal can exercise keepalived/network ownership behavior first.
  systemd.services.dbus.serviceConfig.WorkingDirectory = lib.mkForce "/";
  systemd.services.dbus-broker.serviceConfig.WorkingDirectory = lib.mkForce "/";
  systemd.services.systemd-networkd.serviceConfig.WorkingDirectory = lib.mkForce "/";
}
