{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-log-storage;

  logDirectories =
    [
      {
        name = "system";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ]
    ++ optional cfg.journal.enable {
      name = "journal";
      mode = "0755";
      user = "root";
      group = "root";
    }
    ++ cfg.extraDirectories;

  tmpfilesRules =
    map (dir: "d ${cfg.mountPoint}/${dir.name} ${dir.mode} ${dir.user} ${dir.group} -") logDirectories;

  setupScript = concatStringsSep "\n" (
    map (dir: ''
      mkdir -p ${cfg.mountPoint}/${dir.name}
      chmod ${dir.mode} ${cfg.mountPoint}/${dir.name}
      chown ${dir.user}:${dir.group} ${cfg.mountPoint}/${dir.name}
    '') logDirectories
  );

  directoryModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Directory name created under the log-storage mount point.";
      };

      mode = mkOption {
        type = types.str;
        default = "0755";
        description = "Filesystem mode applied to the directory.";
      };

      user = mkOption {
        type = types.str;
        default = "root";
        description = "Owner user for the directory.";
      };

      group = mkOption {
        type = types.str;
        default = "root";
        description = "Owner group for the directory.";
      };
    };
  };
in
{
  options.services.router-log-storage = {
    enable = mkEnableOption "secondary log-storage layout for routers";

    mountPoint = mkOption {
      type = types.str;
      default = "/var/log/router";
      description = "Mount point for persistent router log storage.";
    };

    device = mkOption {
      type = types.str;
      description = "Filesystem device or by-uuid path for the log-storage volume.";
    };

    fsType = mkOption {
      type = types.str;
      default = "ext4";
      description = "Filesystem type for the log-storage volume.";
    };

    mountOptions = mkOption {
      type = types.listOf types.str;
      default = [ "noatime" "nofail" "x-systemd.automount" ];
      description = "Mount options used for the log-storage volume.";
    };

    neededForBoot = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the log-storage filesystem is required during boot.";
    };

    serviceName = mkOption {
      type = types.str;
      default = "setup-router-logs";
      description = "Name of the oneshot service that prepares directories on the log-storage volume.";
    };

    journal = {
      enable = mkEnableOption "persistent journal bind-mount on the log-storage volume";

      systemMaxUse = mkOption {
        type = types.str;
        default = "2G";
        description = "Journald SystemMaxUse value when journal persistence is enabled.";
      };

      runtimeMaxUse = mkOption {
        type = types.str;
        default = "100M";
        description = "Journald RuntimeMaxUse value when journal persistence is enabled.";
      };

      bindMountPath = mkOption {
        type = types.str;
        default = "/var/log/journal";
        description = "Path where the persistent journal bind mount should appear.";
      };
    };

    extraDirectories = mkOption {
      type = types.listOf directoryModule;
      default = [ ];
      description = "Additional per-service directories created on the log-storage volume.";
    };
  };

  config = mkIf cfg.enable {
    fileSystems.${cfg.mountPoint} = {
      device = cfg.device;
      fsType = cfg.fsType;
      options = cfg.mountOptions;
      neededForBoot = cfg.neededForBoot;
    };

    services.journald.extraConfig = mkIf cfg.journal.enable ''
      Storage=persistent
      SystemMaxUse=${cfg.journal.systemMaxUse}
      RuntimeMaxUse=${cfg.journal.runtimeMaxUse}
    '';

    fileSystems.${cfg.journal.bindMountPath} = mkIf cfg.journal.enable {
      device = "${cfg.mountPoint}/journal";
      fsType = "none";
      options = [ "bind" "nofail" "x-systemd.automount" ];
      depends = [ cfg.mountPoint ];
    };

    systemd.services.${cfg.serviceName} = {
      description = "Prepare router log directories on secondary storage";
      after = [ "${escapeSystemdPath cfg.mountPoint}.mount" ];
      wants = [ "${escapeSystemdPath cfg.mountPoint}.mount" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${setupScript}
      '';
    };

    systemd.tmpfiles.rules = tmpfilesRules;
  };
}
