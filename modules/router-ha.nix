{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-ha;
  runtimeDir = "/run/router-ha";
  roleStateFile = "${runtimeDir}/role";
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  hasRouterBgp = hasAttrByPath [ "services" "router-bgp" "enable" ] options;
  hasRouterNdpProxy = hasAttrByPath [ "services" "router-ndp-proxy" "enable" ] options;
  bgpSingleActiveOwner =
    hasRouterBgp
    && (config.services.router-bgp.enable or false)
    && (config.services.router-bgp.ha.singleActiveOwner or false);
  ndpProxySingleActiveOwner =
    hasRouterNdpProxy
    && (config.services.router-ndp-proxy.enable or false)
    && (config.services.router-ndp-proxy.ha.singleActiveOwner or false);
  bgpAsn = if bgpSingleActiveOwner then config.services.router-bgp.asn else 0;
  bgpNeighborIps = if bgpSingleActiveOwner then attrNames (config.services.router-bgp.neighbors or { }) else [ ];

  bgpPromoteScript = pkgs.writeShellScript "keepalived-bgp-promote" ''
    echo "BGP: Promoting — activating neighbors..."
    ${concatMapStringsSep "\n" (ip: ''
      ${pkgs.frr}/bin/vtysh -c "configure terminal" -c "router bgp ${toString bgpAsn}" -c "no neighbor ${ip} shutdown"
    '') bgpNeighborIps}
  '';

  bgpDemoteScript = pkgs.writeShellScript "keepalived-bgp-demote" ''
    echo "BGP: Demoting — shutting down neighbors..."
    ${concatMapStringsSep "\n" (ip: ''
      ${pkgs.frr}/bin/vtysh -c "configure terminal" -c "router bgp ${toString bgpAsn}" -c "neighbor ${ip} shutdown"
    '') bgpNeighborIps}
  '';

  writeRoleState =
    role:
    pkgs.writeShellScript "router-ha-mark-${role}" ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/install -d -m 0755 ${escapeShellArg runtimeDir}
      ${pkgs.coreutils}/bin/printf '%s\n' ${escapeShellArg role} > ${escapeShellArg roleStateFile}
      ${pkgs.coreutils}/bin/chmod 0644 ${escapeShellArg roleStateFile}
    '';

  startSingleActiveUnits = pkgs.writeShellScript "router-ha-start-single-active-units" ''
    set -euo pipefail
    ${concatMapStringsSep "\n" (unit: ''
      ${pkgs.systemd}/bin/systemctl start ${escapeShellArg unit}
    '') cfg.singleActiveUnits}
  '';

  stopSingleActiveUnits = pkgs.writeShellScript "router-ha-stop-single-active-units" ''
    set -euo pipefail
    ${concatMapStringsSep "\n" (unit: ''
      ${pkgs.systemd}/bin/systemctl stop ${escapeShellArg unit}
    '') cfg.singleActiveUnits}
  '';

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

    singleActiveUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "inadyn.service" ];
      description = ''
        Consumer-owned systemd units that should only run on the active router.
        `router-ha` starts them on master promotion and stops them on backup or
        fault transitions. This is intentionally generic and does not claim a
        typed ownership model for every LAN-facing service.
      '';
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

      systemd.services.router-ha-initial-role-state = {
        description = "Seed router HA runtime role state";
        wantedBy = [ "multi-user.target" ];
        before = [ "keepalived.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${writeRoleState cfg.role}
        '';
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
            ${optionalString (cfg.wan.enable || bgpSingleActiveOwner || ndpProxySingleActiveOwner || cfg.singleActiveUnits != [ ]) ''
              notify_master "${pkgs.writeShellScript "keepalived-master" ''
                ${writeRoleState "master"}
                ${optionalString cfg.wan.enable ''
                  echo "Transitioning to MASTER: Bringing up WAN ${cfg.wan.interface}..."
                  ${optionalString (cfg.wan.clonedMac != null) ''
                    ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} address ${cfg.wan.clonedMac}
                  ''}
                  ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} up
                  ${pkgs.systemd}/bin/systemctl restart systemd-networkd
                ''}
                ${optionalString bgpSingleActiveOwner ''
                  ${bgpPromoteScript}
                ''}
                ${optionalString ndpProxySingleActiveOwner ''
                  ${pkgs.systemd}/bin/systemctl start router-ndp-proxy.service
                ''}
                ${optionalString (cfg.singleActiveUnits != [ ]) ''
                  ${startSingleActiveUnits}
                ''}
              ''}"
              notify_backup "${pkgs.writeShellScript "keepalived-backup" ''
                ${writeRoleState "backup"}
                ${optionalString cfg.wan.enable ''
                  echo "Transitioning to BACKUP: Bringing down WAN ${cfg.wan.interface}..."
                  ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} down
                ''}
                ${optionalString bgpSingleActiveOwner ''
                  ${bgpDemoteScript}
                ''}
                ${optionalString ndpProxySingleActiveOwner ''
                  ${pkgs.systemd}/bin/systemctl stop router-ndp-proxy.service
                ''}
                ${optionalString (cfg.singleActiveUnits != [ ]) ''
                  ${stopSingleActiveUnits}
                ''}
              ''}"
              notify_fault "${pkgs.writeShellScript "keepalived-fault" ''
                ${writeRoleState "fault"}
                ${optionalString cfg.wan.enable ''
                  echo "Transitioning to FAULT: Bringing down WAN ${cfg.wan.interface}..."
                  ${pkgs.iproute2}/bin/ip link set ${cfg.wan.interface} down
                ''}
                ${optionalString bgpSingleActiveOwner ''
                  ${bgpDemoteScript}
                ''}
                ${optionalString ndpProxySingleActiveOwner ''
                  ${pkgs.systemd}/bin/systemctl stop router-ndp-proxy.service
                ''}
                ${optionalString (cfg.singleActiveUnits != [ ]) ''
                  ${stopSingleActiveUnits}
                ''}
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
