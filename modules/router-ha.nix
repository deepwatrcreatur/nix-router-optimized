{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-ha;
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  virtualIpAddress = builtins.head (lib.splitString "/" cfg.virtualIp);
  virtualIpIsIpv6 = hasInfix ":" virtualIpAddress;
in
{
  options.services.router-ha = {
    enable = mkEnableOption "High Availability using VRRP (Keepalived)";

    role = mkOption {
      type = types.enum [ "master" "backup" ];
      description = "The VRRP role of this node.";
    };

    virtualIp = mkOption {
      type = types.str;
      example = "10.10.10.1/16";
      description = "The virtual IP (VIP) shared between master and backup.";
    };

    vrrpInterface = mkOption {
      type = types.str;
      example = "enp6s18";
      description = "The interface on which to run VRRP.";
    };

    vrrpId = mkOption {
      type = types.int;
      default = 51;
      description = "The VRRP Virtual Router ID (VRID). Must be same on both nodes.";
    };

    vrrpPassword = mkOption {
      type = types.str;
      default = "nix-router-ha";
      description = "The VRRP authentication password.";
    };

    priority = mkOption {
      type = types.int;
      default = if cfg.role == "master" then 100 else 50;
      description = "The VRRP priority (higher wins). Defaults based on role.";
    };

    wan = {
      enable = mkEnableOption "WAN High Availability (MAC cloning and interface toggle)";
      interface = mkOption {
        type = types.str;
        example = "enp2s0";
        description = "The WAN interface to manage.";
      };
      clonedMac = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "00:11:22:33:44:55";
        description = "The Golden MAC address to clone when this node is Master.";
      };
    };

    keaSync = {
      enable = mkEnableOption "Automatic Kea DHCP lease synchronization with peer";
      peerAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The management/control-plane IP of the other router node.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      boot.kernel.sysctl = {
        "net.ipv4.ip_nonlocal_bind" = mkIf (!virtualIpIsIpv6) 1;
        "net.ipv6.ip_nonlocal_bind" = mkIf virtualIpIsIpv6 1;
      };

      # Keepalived for VRRP
      services.keepalived = {
        enable = true;
        vrrpInstances.main = {
          state = if cfg.role == "master" then "MASTER" else "BACKUP";
          interface = cfg.vrrpInterface;
          virtualRouterId = cfg.vrrpId;
          priority = cfg.priority;
          virtualIps = [
            { addr = cfg.virtualIp; }
          ];
          extraConfig = ''
            authentication {
              auth_type PASS
              auth_pass ${cfg.vrrpPassword}
            }
            ${optionalString cfg.wan.enable ''
              notify_master "${pkgs.writeShellScript "keepalived-master" ''
                echo "Transitioning to MASTER: Bringing up WAN ${cfg.wan.interface}..."
                ${optionalString (cfg.wan.clonedMac != null) ''
                  ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} address ${cfg.wan.clonedMac}
                ''}
                ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} up
                ${pkgs.systemd}/bin/systemctl restart systemd-networkd
              ''}"
              notify_backup "${pkgs.writeShellScript "keepalived-backup" ''
                echo "Transitioning to BACKUP: Bringing down WAN ${cfg.wan.interface}..."
                ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} down
              ''}"
              notify_fault "${pkgs.writeShellScript "keepalived-fault" ''
                echo "Transitioning to FAULT: Bringing down WAN ${cfg.wan.interface}..."
                ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} down
              ''}"
            ''}
          '';
        };
      };
    }

    # Firewall integration
    (if hasRouterFirewall then {
      services.router-firewall = mkIf (config.services.router-firewall.enable or false) {
        # VRRP uses multicast/protocol 112
        extraInputRules = ''
          ip protocol vrrp accept comment "Allow VRRP traffic"
        '' + optionalString cfg.keaSync.enable ''
          tcp dport 8000 accept comment "Allow Kea HA sync"
        '';
      };
    } else { })
  ]);
}
