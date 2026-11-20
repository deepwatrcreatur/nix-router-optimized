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

  masterRoleScript = writeRoleState "master";
  backupRoleScript = writeRoleState "backup";
  faultRoleScript = writeRoleState "fault";

  startSingleActiveUnits = pkgs.writeShellScript "router-ha-start-single-active-units" ''
    set -euo pipefail
    rc=0
    ${concatMapStringsSep "\n" (unit: ''
      if ! ${pkgs.systemd}/bin/systemctl --no-block start ${escapeShellArg unit}; then
        rc=1
      fi
    '') cfg.singleActiveUnits}
    exit "$rc"
  '';

  stopSingleActiveUnits = pkgs.writeShellScript "router-ha-stop-single-active-units" ''
    set -euo pipefail
    rc=0
    ${concatMapStringsSep "\n" (unit: ''
      if ! ${pkgs.systemd}/bin/systemctl --no-block stop ${escapeShellArg unit}; then
        rc=1
      fi
    '') cfg.singleActiveUnits}
    exit "$rc"
  '';

  notifyMasterScript = pkgs.writeShellScript "keepalived-master" ''
    ${masterRoleScript}
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
  '';

  demoteActiveOwnership = role: roleScript: pkgs.writeShellScript "router-ha-demote-${role}" ''
    ${roleScript}
    ${optionalString cfg.wan.enable ''
      echo "Transitioning away from MASTER: Bringing down WAN ${cfg.wan.interface}..."
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
  '';

  notifyBackupScript = demoteActiveOwnership "backup" backupRoleScript;
  notifyFaultScript = demoteActiveOwnership "fault" faultRoleScript;
  keepalivedStopScript = demoteActiveOwnership "stop" backupRoleScript;

  usePasswordFile = cfg.vrrpPasswordFile != null;
  # INVARIANT: router-ha-vrrp-secret writes "$dir/vrrp-secret.env".
  vrrpSecretEnv = "${runtimeDir}/vrrp-secret.env";
  # Mirrors the runtime check in router-ha-vrrp-secret so the inline password
  # cannot break keepalived.conf parsing either. INVARIANT: no `"` or `\`, so
  # the value cannot escape the quoted auth_pass (braces stay literal there).
  vrrpPasswordCharsOk = pw: builtins.match "[!-~]+" pw != null && builtins.match ".*[\"'\\\\$#!].*" pw == null;

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

    vrrpPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/agenix/router-vrrp-password";
      description = ''
        Runtime path (a string such as `/run/agenix/...`, not a Nix path
        literal, which would place it in the store) of a file holding the VRRP authentication password (one line). It is loaded
        as a systemd credential and substituted into keepalived's runtime config,
        so it never enters the Nix store. Keepalived uses only the first 8
        characters (VRRPv2 `auth_type PASS`). Allowed characters: printable
        ASCII without whitespace, quotes, backslash, `$`, `#` or `!`.

        PASS authentication is sent in clear text on the VRRP link. It stops
        accidental cross-talk between VRRP groups, not an attacker on the LAN.
        Run VRRP only on a trusted segment.
      '';
    };

    vrrpPassword = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Deprecated: the password is written into keepalived.conf in the
        world-readable Nix store. Use `vrrpPasswordFile`. There is no default;
        pairs that relied on the old default `nix-router-ha` must set
        `vrrpPasswordFile` (or, temporarily, this option) on both nodes.
      '';
    };

    priority = mkOption {
      type = types.int;
      default = if cfg.role == "master" then 100 else 50;
      description = "The VRRP priority (higher wins). Defaults based on role.";
    };

    preemptDelay = mkOption {
      type = types.nullOr (types.ints.between 0 1000);
      default = null;
      example = 300;
      description = ''
        Seconds a recovered higher-priority node waits as BACKUP before taking
        the VIP back (keepalived `preempt_delay`, max 1000). Setting it makes
        every node start as BACKUP so priority alone decides; keepalived
        ignores `preempt_delay` on an instance that starts as MASTER. `null`
        keeps the role-based initial state and immediate preemption.
      '';
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
      assertions = [
        {
          # WHY: no default password. A rolling upgrade where one node has auth
          # and the other has none makes both nodes MASTER, so make the choice
          # explicit instead of silently changing the wire format.
          assertion = (cfg.vrrpPasswordFile != null) != (cfg.vrrpPassword != null);
          message = "services.router-ha: set exactly one of vrrpPasswordFile (recommended) or the deprecated vrrpPassword. The old default \"nix-router-ha\" was removed; see docs/router-ha-pair-guide.md#vrrp-authentication.";
        }
        {
          # SECURITY: a path literal such as ./vrrp-password resolves into the
          # world-readable store (flake sources live there).
          assertion = cfg.vrrpPasswordFile == null || !(hasPrefix builtins.storeDir (toString cfg.vrrpPasswordFile));
          message = "services.router-ha.vrrpPasswordFile must be a runtime path (e.g. /run/agenix/...), not a file in the Nix store; use a string path, not a path literal.";
        }
        {
          assertion = cfg.vrrpPassword == null || vrrpPasswordCharsOk cfg.vrrpPassword;
          message = "services.router-ha.vrrpPassword must be printable ASCII without whitespace, quotes, backslash, $, # or !.";
        }
        {
          assertion =
            let
              vipIp = head (splitString "/" cfg.virtualIp);
              routedIfaces = config.services.router-networking.routedInterfaces or { };
              wanIfaces = config.services.router-networking.wanInterfaces or { };
              allStaticIps =
                (map (i: head (splitString "/" i.ipv4Address)) (attrValues routedIfaces))
                ++ (map (i: head (splitString "/" i.ipv4Address)) (filter (w: w.mode == "static" && w.ipv4Address != null) (attrValues wanIfaces)));
            in
              !elem vipIp allStaticIps;
          message = "services.router-ha: VRRP virtual IP (${cfg.virtualIp}) collides with a static interface IP address.";
        }
        {
          assertion =
            let
              routedIfaces = config.services.router-networking.routedInterfaces or { };
              matching = filter (i: i.device == cfg.vrrpInterface) (attrValues routedIfaces);
            in
              if matching == [ ] then true
              else
                let
                  targetIface = head matching;
                  ipLib = import ./lib/ip.nix { inherit lib; };
                in
                  ipLib.cidrContains targetIface.ipv4Address cfg.virtualIp;
          message = "services.router-ha: VRRP virtual IP (${cfg.virtualIp}) must be in the same subnet as vrrpInterface ${cfg.vrrpInterface}.";
        }
      ];

      warnings = optional (cfg.vrrpPassword != null)
        "services.router-ha.vrrpPassword puts the VRRP password in the Nix store; use vrrpPasswordFile instead.";

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
          ${backupRoleScript}
        '';
      };

      # Keepalived for VRRP
      services.keepalived = {
        enable = true;
        enableScriptSecurity = true;
        extraGlobalDefs = ''
          script_user root
        '';
        vrrpInstances.main = {
          # INVARIANT: with preemptDelay every node starts BACKUP; keepalived
          # ignores preempt_delay on a MASTER-start instance.
          state = if cfg.role == "master" && cfg.preemptDelay == null then "MASTER" else "BACKUP";
          interface = cfg.vrrpInterface;
          virtualRouterId = cfg.vrrpId;
          priority = cfg.priority;
          virtualIps = [
            { addr = cfg.virtualIp; }
          ];
          extraConfig = ''
            ${optionalString (cfg.preemptDelay != null) "preempt_delay ${toString cfg.preemptDelay}"}
            authentication {
              auth_type PASS
              auth_pass "${if usePasswordFile then "$ROUTER_HA_VRRP_PASS" else cfg.vrrpPassword}"
            }
            ${optionalString (cfg.wan.enable || bgpSingleActiveOwner || ndpProxySingleActiveOwner || cfg.singleActiveUnits != [ ]) ''
              notify_master "${notifyMasterScript}"
              notify_backup "${notifyBackupScript}"
              notify_fault "${notifyFaultScript}"
            ''}
          '';
        };
      };

      systemd.services.keepalived.serviceConfig.ExecStopPost = [
        "+${keepalivedStopScript}"
      ];
    }

    (mkIf usePasswordFile {
      # SECURITY: the upstream module envsubsts secretFile into
      # /run/keepalived/keepalived.conf (umask 077). systemd reads
      # EnvironmentFile before ExecStartPre, so a separate unit renders it.
      services.keepalived.secretFile = vrrpSecretEnv;

      systemd.services.router-ha-vrrp-secret = {
        description = "Render the router HA VRRP password for keepalived";
        before = [ "keepalived.service" ];
        requiredBy = [ "keepalived.service" ];
        # WHY: PartOf re-renders the secret whenever keepalived restarts, so a
        # rotated password file is picked up without a reboot.
        partOf = [ "keepalived.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = [ "vrrp-password:${toString cfg.vrrpPasswordFile}" ];
          UMask = "0077";
        };
        script = ''
          set -euo pipefail
          dir=${escapeShellArg runtimeDir}
          pw=$(${pkgs.coreutils}/bin/head -n1 "$CREDENTIALS_DIRECTORY/vrrp-password" | ${pkgs.coreutils}/bin/tr -d '\r')
          if [ -z "$pw" ]; then
            echo "router-ha: VRRP password file is empty" >&2
            exit 1
          fi
          case "$pw" in
            *[!!-~]* | *[\"\'\\\$\#\!]*)
              echo "router-ha: VRRP password must be printable ASCII without whitespace, quotes, backslash, \$, # or !" >&2
              exit 1
              ;;
          esac
          if [ "''${#pw}" -gt 8 ]; then
            echo "router-ha: keepalived uses only the first 8 characters of the VRRP password" >&2
          fi
          ${pkgs.coreutils}/bin/install -d -m 0755 "$dir"
          ${pkgs.coreutils}/bin/printf 'ROUTER_HA_VRRP_PASS=%s\n' "$pw" > "$dir/vrrp-secret.env.tmp"
          ${pkgs.coreutils}/bin/chmod 0600 "$dir/vrrp-secret.env.tmp"
          ${pkgs.coreutils}/bin/mv "$dir/vrrp-secret.env.tmp" "$dir/vrrp-secret.env"
        '';
      };

      systemd.services.keepalived.after = [ "router-ha-vrrp-secret.service" ];
    })

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
