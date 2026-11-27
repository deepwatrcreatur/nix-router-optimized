{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-ha;
  runtimeDir = "/run/router-ha";
  masterPendingFile = "${runtimeDir}/master-pending";
  roleStateFile = "${runtimeDir}/role";
  # Created by keepalived; read by notifyFifoReader.
  notifyFifo = "${runtimeDir}/notify.fifo";
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  hasRouterBgp = hasAttrByPath [ "services" "router-bgp" "enable" ] options;
  hasRouterNdpProxy = hasAttrByPath [ "services" "router-ndp-proxy" "enable" ] options;
  hasRouterKea = hasAttrByPath [ "services" "router-kea" "enable" ] options;
  keaHaEnabled =
    hasRouterKea
    && (config.services.router-kea.enable or false)
    && (config.services.router-kea.dhcp4.ha.enable or false);
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

  cts = cfg.conntrackSync;
  # GOTCHA: a bulk resync copies the MASTER's kernel table, so cached flows
  # that were in the nftables flowtable carry IPS_OFFLOAD. conntrack-tools
  # 1.4.8 commits them unchanged; current kernels ignore status bits userspace
  # may not set, so the commit succeeds (vm-router-ha-conntrack-sync proves it).
  conntrackdSocket = "/run/conntrackd/conntrackd.ctl";
  conntrackdConf = pkgs.writeText "conntrackd.conf" ''
    Sync {
      Mode FTFW {
        DisableExternalCache Off
        CommitTimeout 1800
        PurgeTimeout 5
      }
      UDP {
        IPv4_address ${cts.localAddress}
        IPv4_Destination_Address ${cts.peerAddress}
        Port ${toString cts.port}
        Interface ${cts.interface}
        SndSocketBuffer 1249280
        RcvSocketBuffer 1249280
        Checksum on
      }
    }
    General {
      HashSize 32768
      HashLimit 131072
      LogFile off
      Syslog on
      LockFile /run/conntrackd/conntrackd.lock
      UNIX {
        Path ${conntrackdSocket}
      }
      NetlinkBufferSize 2097152
      NetlinkBufferSizeMaxGrowth 8388608
      Filter From Userspace {
        Protocol Accept {
          TCP
          UDP
          ICMP
          IPv6-ICMP
        }
        Address Ignore {
          ${concatMapStringsSep "\n      " (a: (if hasInfix ":" a then "IPv6_address " else "IPv4_address ") + a) ([
            "127.0.0.1"
            "::1"
            cts.localAddress
            cts.peerAddress
          ] ++ cts.ignoreAddresses)}
        }
      }
    }
  '';
  # Never fails or blocks a transition: conntrackd may be down, and a slow
  # commit must not hold the WAN back for long.
  conntrackdCtl =
    args:
    "${pkgs.coreutils}/bin/timeout 20 ${cts.package}/bin/conntrackd -C ${conntrackdConf} ${args} || echo \"router-ha: conntrackd ${args} failed\" >&2";

  notifyMasterScript = pkgs.writeShellScript "keepalived-master" ''
    ${masterRoleScript}
    # INVARIANT: present only while a promotion runs; the FIFO reader
    # finishes an interrupted one (see notifyFifoReader).
    ${pkgs.coreutils}/bin/touch ${escapeShellArg masterPendingFile}
    ${optionalString cts.enable ''
      # INVARIANT: commit the peer's flows into the kernel before the WAN
      # comes up, so the first returning packets find their NAT entries.
      ${conntrackdCtl "-c"}
      ${conntrackdCtl "-f"}
      ${conntrackdCtl "-R"}
      ${conntrackdCtl "-B"}
    ''}
    ${optionalString cfg.wan.enable ''
      echo "Transitioning to MASTER: Bringing up WAN ${cfg.wan.interface}..."
      ${optionalString (cfg.wan.clonedMac != null) ''
        ${pkgs.iproute2}/bin/ip link set dev ${escapeShellArg cfg.wan.interface} down
        ${pkgs.iproute2}/bin/ip link set dev ${escapeShellArg cfg.wan.interface} address ${escapeShellArg cfg.wan.clonedMac}
      ''}
      # WHY: only the WAN link changes; restarting systemd-networkd here
      # bounced LAN and management at the moment of failover.
      ${pkgs.systemd}/bin/networkctl up ${escapeShellArg cfg.wan.interface}
      # Fresh DHCPv4/DHCPv6/PD with the (possibly cloned) MAC.
      ${pkgs.systemd}/bin/networkctl reconfigure ${escapeShellArg cfg.wan.interface}
      ${optionalString wanHealthEnabled "${pkgs.coreutils}/bin/touch ${escapeShellArg wanUpSinceFile}"}
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
    ${pkgs.coreutils}/bin/rm -f ${escapeShellArg masterPendingFile}
  '';

  demoteActiveOwnership = role: roleScript: pkgs.writeShellScript "router-ha-demote-${role}" ''
    ${roleScript}
    ${pkgs.coreutils}/bin/rm -f ${escapeShellArg masterPendingFile}
    ${optionalString (cts.enable && role != "stop") ''
      # Shorten the kernel timers of flows this node forwarded as MASTER, so
      # they expire; a BACKUP also asks the new MASTER for a full resync.
      ${conntrackdCtl "-t"}
      ${optionalString (role == "backup") (conntrackdCtl "-n")}
    ''}
    ${optionalString cfg.wan.enable ''
      echo "Transitioning away from MASTER: Bringing down WAN ${cfg.wan.interface}..."
      ${pkgs.systemd}/bin/networkctl down ${escapeShellArg cfg.wan.interface} \
        || ${pkgs.iproute2}/bin/ip link set dev ${escapeShellArg cfg.wan.interface} down
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

  hasNotifyHooks = cfg.wan.enable || cts.enable || bgpSingleActiveOwner || ndpProxySingleActiveOwner || cfg.singleActiveUnits != [ ];

  # INVARIANT: one reader applies transitions one at a time, in the order
  # keepalived sent them. Separate notify_* scripts run concurrently, so a
  # MASTER quickly followed by FAULT could raise the WAN after the FAULT
  # script took it down (docs/router-ha-prior-art.md#adopted-from-this-review).
  notifyFifoReader = pkgs.writeShellScript "router-ha-notify-fifo" ''
    fifo="''${!#}"
    while :; do
      # GOTCHA: a reload kills the reader, possibly mid-promotion, and
      # keepalived 2.3.4 replays only non-MASTER states. Finish the promotion
      # if this node still holds the VIP; otherwise the replayed state demotes.
      if [ -e ${escapeShellArg masterPendingFile} ] \
        && ${pkgs.iproute2}/bin/ip -o addr show dev ${escapeShellArg cfg.vrrpInterface} \
          | ${pkgs.gnugrep}/bin/grep -qF ${escapeShellArg " ${virtualIpAddress}/"}; then
        echo "router-ha: finishing an interrupted MASTER promotion"
        ${notifyMasterScript} </dev/null
      fi
      # Lines look like: INSTANCE "main" MASTER 100
      while read -r kind name state _priority; do
        # GOTCHA: the FIFO carries every instance's events; act on ours only.
        [ "$kind" = INSTANCE ] && [ "$name" = '"main"' ] || continue
        echo "router-ha: applying $state"
        # GOTCHA: stdin is the FIFO; a script reading it would eat later events.
        case "$state" in
          MASTER) ${notifyMasterScript} </dev/null ;;
          BACKUP) ${notifyBackupScript} </dev/null ;;
          FAULT) ${notifyFaultScript} </dev/null ;;
          STOP | DELETED) ${keepalivedStopScript} </dev/null ;;
          *) ;;
        esac
      done <"$fifo"
      # GOTCHA: EOF only means keepalived closed its end (reload); reopen.
      ${pkgs.coreutils}/bin/sleep 0.1
    done
  '';

  hc = cfg.wan.healthCheck;
  wanHealthEnabled = cfg.wan.enable && hc.enable;
  # INVARIANT: "1" pins the node's priority to 1 (router_ha_wan_pin fails,
  # weight -253), "0" restores it. Only the health check writes it.
  wanPenaltyFile = "${runtimeDir}/wan-penalty";
  wanFailCountFile = "${runtimeDir}/wan-health-failures";
  # Written by notify_master after the WAN is raised; the startup grace
  # counts from here so slow link setup does not eat into it.
  wanUpSinceFile = "${runtimeDir}/wan-up-since";
  # Seconds as a decimal string for timeout(1) and ping -W, e.g. 800 -> "0.800".
  probeTimeout =
    let
      ms = hc.timeoutMs;
      frac = toString (mod ms 1000);
    in
    "${toString (ms / 1000)}.${fixedWidthString 3 "0" frac}";

  # WHY: a priority drop alone is not enough. A backup that sees a
  # lower-priority master waits preempt_delay before taking over, so with
  # preemptDelay = 300 a dead WAN would stay master for five minutes. The
  # check therefore yields once (exit 1 -> FAULT -> priority-0 advert, the
  # peer takes over at once) and pins the priority to 1 so this node does not
  # preempt straight back. A node that is already pinned never yields again:
  # if the peer is also pinned (the ISP itself is down) or absent, the LAN
  # VIP stays up somewhere instead of both nodes sitting in FAULT.
  wanHealthScript = pkgs.writeShellScript "router-ha-wan-health" ''
    set -u
    PATH=${makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.iproute2 pkgs.iputils pkgs.util-linux ]}
    wan=${escapeShellArg cfg.wan.interface}
    role=$(cat ${escapeShellArg roleStateFile} 2>/dev/null || echo backup)
    penalty=$(cat ${escapeShellArg wanPenaltyFile} 2>/dev/null || echo 0)
    now=$(date +%s)

    set_penalty() {
      printf '%s\n' "$1" > ${escapeShellArg wanPenaltyFile}.tmp
      mv ${escapeShellArg wanPenaltyFile}.tmp ${escapeShellArg wanPenaltyFile}
    }

    if [ "$role" = fault ] && [ "$penalty" = 1 ]; then
      # Stay in FAULT until router_ha_wan_pin has seen the pin; leaving it
      # earlier at full priority could preempt the peer straight back.
      since=$(stat -c %Y ${escapeShellArg wanPenaltyFile} 2>/dev/null || echo 0)
      if [ $((now - since)) -lt 3 ]; then
        exit 1
      fi
    fi

    if [ "$role" != master ]; then
      rm -f ${escapeShellArg wanFailCountFile}
      ${optionalString (hc.retryAfterSec != null) ''
        # The WAN is down on a backup, so it cannot be re-checked here; after
        # retryAfterSec the pin is lifted and the node may preempt (still
        # subject to preemptDelay) to try again.
        if [ "$penalty" = 1 ]; then
          since=$(stat -c %Y ${escapeShellArg wanPenaltyFile} 2>/dev/null || echo "$now")
          if [ $((now - since)) -ge ${toString hc.retryAfterSec} ]; then
            logger -t router-ha "WAN health retry: lifting the priority pin"
            set_penalty 0
          fi
        fi
      ''}
      exit 0
    fi

    # The master has just brought the WAN up; give DHCP time to finish.
    since=$(stat -c %Y ${escapeShellArg roleStateFile} 2>/dev/null || echo 0)
    up=$(stat -c %Y ${escapeShellArg wanUpSinceFile} 2>/dev/null || echo 0)
    [ "$up" -gt "$since" ] && since=$up
    if [ $((now - since)) -lt ${toString hc.startupGraceSec} ]; then
      exit 0
    fi

    healthy=0
    ${if hc.targets == [ ] then ''
      gw=$(ip -4 route show default dev "$wan" | awk '$2 == "via" { print $3; exit }')
      if [ -n "$gw" ]; then
        timeout ${probeTimeout} arping -q -c 1 -w ${toString ((hc.timeoutMs + 999) / 1000)} -I "$wan" "$gw" && healthy=1
      elif [ -n "$(ip -4 route show default dev "$wan")" ]; then
        # GOTCHA: point-to-point WANs (PPPoE) have no gateway to ARP for.
        healthy=1
      fi
    '' else ''
      # Probe all targets in parallel so the check fits in one interval.
      pids=""
      for t in ${escapeShellArgs hc.targets}; do
        ping -q -n -c 1 -W ${probeTimeout} -I "$wan" "$t" >/dev/null 2>&1 &
        pids="$pids $!"
      done
      for p in $pids; do
        wait "$p" && healthy=1
      done
    ''}

    if [ "$healthy" = 1 ]; then
      rm -f ${escapeShellArg wanFailCountFile}
      if [ "$penalty" != 0 ]; then
        logger -t router-ha "WAN ${cfg.wan.interface} healthy again: restoring priority"
        set_penalty 0
      fi
      exit 0
    fi

    fails=$(( $(cat ${escapeShellArg wanFailCountFile} 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$fails" > ${escapeShellArg wanFailCountFile}
    if [ "$fails" -lt ${toString hc.failures} ] || [ "$penalty" = 1 ]; then
      exit 0
    fi
    logger -t router-ha "WAN ${cfg.wan.interface} failed $fails checks: yielding to the peer"
    set_penalty 1
    exit 1
  '';

  usePasswordFile = cfg.vrrpPasswordFile != null;
  # INVARIANT: router-ha-vrrp-secret writes "$dir/vrrp-secret.env".
  vrrpSecretEnv = "${runtimeDir}/vrrp-secret.env";
  # Mirrors the runtime check in router-ha-vrrp-secret so the inline password
  # cannot break keepalived.conf parsing either. INVARIANT: no `"` or `\`, so
  # the value cannot escape the quoted auth_pass (braces stay literal there).
  vrrpPasswordCharsOk = pw: builtins.match "[!-~]+" pw != null && builtins.match ".*[\"'\\\\$#!].*" pw == null;

  garpKeywords = {
    masterDelay = "garp_master_delay";
    masterRepeat = "garp_master_repeat";
    lowerPrioDelay = "garp_lower_prio_delay";
    lowerPrioRepeat = "garp_lower_prio_repeat";
    masterRefresh = "garp_master_refresh";
    masterRefreshRepeat = "garp_master_refresh_repeat";
  };
  # WHY: keepalived already sends GARP/unsolicited NA on promotion; tune it
  # here rather than adding arping/ndisc6 notify scripts (discussion 21 Q3).
  garpConfig = concatStringsSep "\n" (
    mapAttrsToList (name: keyword: "${keyword} ${toString cfg.garp.${name}}") (
      filterAttrs (name: _: cfg.garp.${name} != null) garpKeywords
    )
  );

  hasRouterNetworking = hasAttrByPath [ "services" "router-networking" "enable" ] options;
  # INVARIANT: mirrors router-networking's "10-router-wan-<name>" naming and
  # its effectiveWans = { primary = wan; } // wans.
  autoWanNetwork =
    if hasRouterNetworking && config.services.router-networking.enable then
      let
        rn = config.services.router-networking;
        matching = filterAttrs (_: w: w.device == cfg.wan.interface && w.manageWithNetworkd) (
          { primary = rn.wan; } // rn.wans
        );
      in
      if matching != { } then "10-router-wan-${head (attrNames matching)}" else null
    else
      null;

  virtualIpAddress = builtins.head (lib.splitString "/" cfg.virtualIp);
  virtualIpIsIpv6 = hasInfix ":" virtualIpAddress;
  # Canonical text of a bare address in the VIP's family, or null if it is
  # not one (prefix length, other family, malformed).
  canonicalVrrpAddress =
    addr:
    if hasInfix "/" addr then
      null
    else if virtualIpIsIpv6 then
      let
        parsed = builtins.tryEval (toLower (lib.network.ipv6.fromString addr).address);
      in
      if hasInfix ":" addr && parsed.success then parsed.value else null
    else
      let
        octets = builtins.match "(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})" addr;
      in
      if octets != null && all (o: toInt o <= 255) octets then
        concatMapStringsSep "." (o: toString (toInt o)) octets
      else
        null;

  # INVARIANT: mirrors router-networking's "20-router-<name>" naming.
  autoVrrpNetwork =
    if hasRouterNetworking && config.services.router-networking.enable then
      let
        matching = filterAttrs (_: iface: iface.device == cfg.vrrpInterface) config.services.router-networking.routedInterfaces;
      in
      if matching != { } then "20-router-${head (attrNames matching)}" else null
    else
      null;
  vrrpNet = if cfg.vrrpNetwork == null then { } else config.systemd.network.networks.${cfg.vrrpNetwork} or { };

  ra = cfg.routerAdvertisements;
  # WHY: docs/router-ha-pair-guide.md#peer-wait. Holds keepalived until the peer is
  # audible, so the master-down timer cannot bypass preempt_delay while the
  # LAN port is not forwarding yet. Never fails: a silent peer may be dead.
  peerWaitScript = pkgs.writeShellScript "router-ha-peer-wait" ''
    set -u
    deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString cfg.peerWaitSec} ))
    # VRRP's VRID is the second byte after the IP header. keepalived sends
    # in the VIP's family; IPv6 VRRP (v3) carries no extension headers.
    filter='${
      if virtualIpIsIpv6 then
        "ip6 and ip6[6] = 112 and ip6[41] = ${toString cfg.vrrpId}"
      else
        "ip proto 112 and ip[((ip[0] & 0xf) << 2) + 1] = ${toString cfg.vrrpId}"
    }'
    while :; do
      left=$(( deadline - $(${pkgs.coreutils}/bin/date +%s) ))
      if [ "$left" -le 0 ]; then
        echo "router-ha: no VRRP advert for VRID ${toString cfg.vrrpId} on ${cfg.vrrpInterface} in ${toString cfg.peerWaitSec} s; starting keepalived"
        exit 0
      fi
      # GOTCHA: promiscuous (no -p): the NIC drops the VRRP group until
      # something joins the group, and keepalived has not started yet.
      if ${pkgs.coreutils}/bin/timeout "$left" ${pkgs.tcpdump}/bin/tcpdump -i ${escapeShellArg cfg.vrrpInterface} -c 1 -n "$filter" >/dev/null 2>&1; then
        echo "router-ha: heard a VRRP advert on ${cfg.vrrpInterface}; starting keepalived"
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
  raOwner = ra.mode == "vrrp-owner";
  raOwnerUnit = "router-ha-ra-owner.service";
  # INVARIANT: mirrors router-networking's "20-router-<name>" naming.
  autoRaNetworks =
    if hasRouterNetworking && config.services.router-networking.enable then
      mapAttrsToList (name: _: "20-router-${name}") (
        filterAttrs (_: iface: iface.ipv6SendRA) config.services.router-networking.routedInterfaces
      )
    else
      [ ];
  isTrue = v: v == true || elem v [ "yes" "true" "on" "1" ];
  raSendsRa = n: isTrue (config.systemd.network.networks.${n}.networkConfig.IPv6SendRA or false);
  raSenders = filter (n: !(raOwner && elem n ra.networks)) (
    attrNames (filterAttrs (n: _: raSendsRa n) config.systemd.network.networks)
  );
  unknownRaNetworks = filter (
    n: (config.systemd.network.networks.${n}.matchConfig or { }) == { }
  ) ra.networks;
  silentRaNetworks = filter (n: !raSendsRa n) ra.networks;
  # The MASTER's router lifetime: router-networking's routerLifetimeSec, else
  # empty, which resets networkd to its default (1800 s).
  masterRouterLifetime =
    n:
    let
      routed = config.services.router-networking.routedInterfaces or { };
      name = removePrefix "20-router-" n;
      lifetime = if hasPrefix "20-router-" n && routed ? ${name} then routed.${name}.routerLifetimeSec else null;
      lifetime' = ra.masterRouterLifetimeSec.${n} or lifetime;
    in
    if lifetime' == null then "" else toString lifetime';
  vll = ra.virtualLinkLocal;
  # The interface each RA network configures: router-networking's device,
  # else a literal (glob-free) matchConfig.Name.
  raDevice =
    n:
    let
      routed = config.services.router-networking.routedInterfaces or { };
      name = removePrefix "20-router-" n;
      match = config.systemd.network.networks.${n}.matchConfig.Name or null;
    in
    if hasPrefix "20-router-" n && routed ? ${name} then
      routed.${name}.device
    else if isString match && builtins.match ".*[][*? ].*" match == null then
      match
    else
      null;
  unresolvedRaNetworks = filter (n: raDevice n == null) ra.networks;
  badKeepRaNetworks = filter (
    n: !elem (config.systemd.network.networks.${n}.networkConfig.KeepConfiguration or "static") [ "static" "yes" true ]
  ) ra.networks;
  raDevices = unique (filter (d: d != null) (map raDevice ra.networks));
  # WHY: docs/router-ha-ownership.md#virtual-link-local. Clients learn one
  # default router, the shared link-local, and keep it across failovers;
  # a MASTER that dies cannot send the lifetime-0 RA that would retract its
  # own address. Added before networkd advertises and removed before the
  # final RA, so the MASTER advertises from it (the kernel picks the newest
  # link-local) and the final RA retracts the node's own address, not it.
  # GOTCHA: best effort per interface. An absent secondary LAN must not
  # stop promotion before the reload that turns on the MASTER's RAs; its
  # drop-in's Address= adds the address when the link appears.
  vllScript =
    enable:
    concatMapStringsSep "\n" (
      dev:
      if enable then
        ''
          # WHY: Name= may be an alternative name; procfs knows only the
          # primary one.
          if ifname=$(${pkgs.iproute2}/bin/ip -j link show dev ${escapeShellArg dev} 2>/dev/null | ${pkgs.jq}/bin/jq -er '.[0].ifname'); then
            # WHY: unsolicited NA when the address lands, so clients move
            # the shared router to this MAC at once instead of after NUD.
            echo 1 > "/proc/sys/net/ipv6/conf/$ifname/ndisc_notify" || true
            ${pkgs.iproute2}/bin/ip -6 addr replace ${vll}/64 dev "$ifname" nodad \
              || echo "router-ha: cannot add ${vll} to $ifname" >&2
          else
            echo "router-ha: ${dev} is absent; networkd adds ${vll} when it appears" >&2
          fi
        ''
      else
        "${pkgs.iproute2}/bin/ip -6 addr del ${vll}/64 dev ${escapeShellArg dev} 2>/dev/null || true"
    ) raDevices;
  # WHY: the static config advertises router lifetime 0 ("not a default
  # router"); only the MASTER's runtime drop-in restores the real lifetime.
  # A node whose LAN link died could not send its final RA, so its BACKUP
  # adverts clear stale client routes once the link returns. `networkctl
  # reload` reconfigures only the matching links, and networkd advertises at
  # once when RA restarts (sd-radv), so clients switch within seconds.
  raOwnerScript =
    enable:
    pkgs.writeShellScript "router-ha-ra-${if enable then "start" else "stop"}" ''
      # Stop is best effort: demotion must finish even if networkd is gone.
      set -u${optionalString enable "e"}
      ${optionalString (vll != null && !enable) (vllScript false)}
      ${concatMapStringsSep "\n" (
        n:
        let
          dir = "/run/systemd/network/${n}.network.d";
          file = "${dir}/90-router-ha-ra.conf";
        in
        if enable then
          ''
            ${pkgs.coreutils}/bin/install -d -m 0755 ${escapeShellArg dir}
            ${pkgs.coreutils}/bin/printf '[IPv6SendRA]\nRouterLifetimeSec=%s\n' ${escapeShellArg (masterRouterLifetime n)} > ${escapeShellArg file}
            ${optionalString (vll != null) ''
              # WHY: the kernel drops link-local addresses with the carrier;
              # networkd restores this one when a secondary LAN comes back.
              ${pkgs.coreutils}/bin/printf '[Address]\nAddress=%s/64\nDuplicateAddressDetection=none\n' ${vll} >> ${escapeShellArg file}
            ''}
          ''
        else
          "${pkgs.coreutils}/bin/rm -f ${escapeShellArg file}"
      ) ra.networks}
      ${optionalString (vll != null && enable) (vllScript true)}
      ${pkgs.systemd}/bin/networkctl reload ${optionalString (!enable) "|| true"}
    '';
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

    peerWaitSec = mkOption {
      type = types.ints.between 0 600;
      default = if cfg.preemptDelay != null then 60 else 0;
      defaultText = literalExpression "if preemptDelay != null then 60 else 0";
      example = 0;
      description = ''
        Seconds keepalived's start waits for a VRRP advert (this `vrrpId`)
        on `vrrpInterface` before it starts anyway. keepalived only applies
        `preemptDelay` while it hears a MASTER; one that hears nothing for
        three advert intervals becomes MASTER at once. A switch port that
        is still in spanning-tree listening/learning after boot hides the
        peer for longer than that, and a rebooted higher-priority node then
        takes the gateway without the hold. The wait ends at the first
        advert, so a node with a live peer starts at once; a node whose
        peer is down waits the full time. Set 0 on a node without a peer.
      '';
    };

    unicastPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.10.3" ];
      description = ''
        The peer's address on `vrrpInterface`, in the VIP's family and
        without a prefix length. When set, keepalived sends adverts to
        these addresses instead of the VRRP multicast group (224.0.0.18,
        ff02::12). Use it when the LAN does not deliver VRRP multicast
        between the two routers: some switches (IGMP snooping, multicast
        filtering) drop it on one port while UDP multicast and unicast
        still pass. A node that cannot hear its peer becomes MASTER three
        advert intervals after start, which bypasses `preemptDelay` and
        `peerWaitSec`. Set it on both nodes, each listing the other.
      '';
    };

    unicastSrcIp = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.10.10.2";
      description = ''
        Source address for unicast adverts (keepalived `unicast_src_ip`).
        `null` uses the primary address of `vrrpInterface`. Only used with
        `unicastPeers`. Required with an IPv6 VIP: keepalived otherwise
        binds to a link-local address and never receives adverts sent to
        the address the peer lists.
      '';
    };

    conntrackSync = {
      enable = mkEnableOption ''
        conntrackd state sync (FTFW) with the peer, so established flows,
        NAT included, survive a failover. Commits the peer's flows on MASTER
        before the WAN comes up (docs/router-ha-pair-guide.md#connection-state-sync)
      '';

      interface = mkOption {
        type = types.str;
        example = "eno1";
        description = "Interface of the sync link, ideally a dedicated or management segment.";
      };

      localAddress = mkOption {
        type = types.str;
        example = "192.168.100.2";
        description = "This node's IPv4 address on `interface`.";
      };

      peerAddress = mkOption {
        type = types.str;
        example = "192.168.100.3";
        description = "The peer's IPv4 address on `interface`; sync uses unicast UDP to it.";
      };

      port = mkOption {
        type = types.port;
        default = 3780;
        description = "UDP port of the sync link.";
      };

      ignoreAddresses = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "10.10.10.2" ];
        description = ''
          Addresses whose flows are not synced, typically this node's own LAN
          and WAN addresses (flows that end on the router itself). Loopback and
          the sync addresses are always ignored.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.conntrack-tools;
        defaultText = literalExpression "pkgs.conntrack-tools";
        description = "conntrack-tools providing conntrackd.";
      };
    };

    garp =
      let
        garpOption =
          keyword: description:
          mkOption {
            type = types.nullOr types.ints.unsigned;
            default = null;
            description = "${description} Keepalived `${keyword}`; `null` keeps keepalived's default.";
          };
      in
      {
        masterDelay = garpOption "garp_master_delay" "Seconds after becoming MASTER before the second burst of gratuitous ARP/unsolicited NA (0 disables the second burst; keepalived default 5).";
        masterRepeat = garpOption "garp_master_repeat" "Gratuitous ARP/NA messages per burst on becoming MASTER (keepalived default 5).";
        lowerPrioDelay = garpOption "garp_lower_prio_delay" "Delay for the second burst after a lower-priority advert is seen while MASTER (defaults to masterDelay).";
        lowerPrioRepeat = garpOption "garp_lower_prio_repeat" "Messages per burst after a lower-priority advert is seen while MASTER (defaults to masterRepeat).";
        masterRefresh = garpOption "garp_master_refresh" "Seconds between periodic gratuitous ARP/NA refreshes while MASTER (keepalived default 0, no refresh). Useful when a switch or bridge ages out the VIP's MAC entry.";
        masterRefreshRepeat = garpOption "garp_master_refresh_repeat" "Messages per periodic refresh (keepalived default 1).";
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

    vrrpNetwork = mkOption {
      type = types.nullOr types.str;
      default = autoVrrpNetwork;
      defaultText = literalExpression ''"20-router-<name>" of the router-networking routed interface whose device is vrrpInterface, else null'';
      example = "20-lan";
      description = ''
        Attribute name under `systemd.network.networks` of the VRRP
        interface's `.network`. router-ha sets `KeepConfiguration=static` on
        it: otherwise systemd-networkd removes the VIP (an address it did not
        configure) whenever it reconfigures the link or restarts, and
        keepalived drops to BACKUP. Detected automatically for
        `router-networking` routed interfaces.
      '';
    };

    routerAdvertisements = {
      mode = mkOption {
        type = types.nullOr (types.enum [ "vrrp-owner" "both-nodes" ]);
        default = null;
        description = ''
          Who sends IPv6 Router Advertisements on the shared LANs. Required
          when any systemd-networkd network has `IPv6SendRA` enabled.

          - `"vrrp-owner"`: only the VRRP MASTER advertises itself as a
            default router. `networks` advertise router lifetime 0 in their
            static config ("not a default router"); router-ha adds a runtime
            drop-in with the real lifetime on promotion and removes it on
            demotion, so clients switch routers within seconds.
          - `"both-nodes"`: both nodes advertise, as before. Clients then use
            either node as their IPv6 default router, including a backup
            whose WAN is down; only choose this if each node has its own
            working IPv6 uplink.
        '';
      };

      networks = mkOption {
        type = types.listOf types.str;
        default = autoRaNetworks;
        defaultText = literalExpression ''
          [ "20-router-<name>" for each services.router-networking.routedInterfaces.<name> with ipv6SendRA ]
        '';
        example = [ "20-router-lan" ];
        description = "systemd-networkd network names whose RAs follow the VRRP MASTER in `\"vrrp-owner\"` mode.";
      };

      virtualLinkLocal = mkOption {
        type = types.nullOr (types.strMatching "fe80::[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,3}");
        default = "fe80::1";
        example = "fe80::53";
        description = ''
          Link-local address the MASTER holds on every network in
          `networks` and sends its RAs from (`"vrrp-owner"` only). Clients
          then know a single IPv6 default router that moves with VRRP, so a
          MASTER that dies without a final RA leaves no stale route behind;
          an unsolicited NA moves it to the new MASTER's MAC. Pick an address
          no other host on those links uses. `null` advertises from each
          node's own link-local address: clients then keep a dead MASTER's
          route until its router lifetime expires.
        '';
      };

      masterRouterLifetimeSec = mkOption {
        type = types.attrsOf (types.ints.between 0 9000);
        default = { };
        example = {
          "20-lan" = 600;
        };
        description = ''
          Router lifetime the MASTER advertises, per network in `networks`.
          `"vrrp-owner"` forces the static `RouterLifetimeSec` to 0, so a value
          set on the network itself is not seen. Unset networks use
          router-networking's `routerLifetimeSec`, else networkd's default
          (1800 s).
        '';
      };
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
      sharedDhcpIdentity = mkOption {
        type = types.bool;
        default = cfg.wan.clonedMac != null;
        defaultText = literalExpression "wan.clonedMac != null";
        description = ''
          Give the WAN's DHCPv4 and DHCPv6 clients the same identity on both
          nodes: a link-layer DUID built from `clonedMac` and an IAID from its
          last four bytes. Without it each node sends its own machine-id
          DUID, so an ISP that binds the lease or the delegated prefix to the
          DUID hands the new master a different prefix and LAN clients
          renumber. Turning it on changes the DUID once, which can move the
          delegated prefix at the next renewal.
        '';
      };
      network = mkOption {
        type = types.nullOr types.str;
        default = autoWanNetwork;
        defaultText = literalExpression ''"10-router-wan-<name>" of the router-networking WAN whose device is wan.interface, else null'';
        example = "10-wan";
        description = ''
          Attribute name under `systemd.network.networks` of the WAN's
          `.network`. router-ha sets `ActivationPolicy=manual` on it, so
          systemd-networkd never brings the WAN up by itself (at boot or on a
          networkd restart); only VRRP promotion runs `networkctl up`.
          Detected automatically for WANs managed by `router-networking`.
        '';
      };

      healthCheck = {
        enable = mkEnableOption ''
          the WAN health check. While this node is master, it checks the WAN
          every `interval` seconds; after `failures` failed checks in a row it
          hands the VIP and WAN to the peer immediately (regardless of
          `preemptDelay`) and pins its own priority to 1. A pinned node never
          yields again, so if both WANs are bad (an ISP outage) or the peer is
          missing, one node stays master. See docs/router-ha-pair-guide.md'';

        targets = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "1.1.1.1" "9.9.9.9" ];
          description = ''
            Addresses pinged out of the WAN interface; the WAN is healthy if
            any one answers. Empty (the default) ARPs the IPv4 default gateway
            learned on the WAN instead, which catches a dead link, NIC or
            lease without depending on remote hosts. With targets, an outage
            beyond the ISP gateway also triggers failover, although the peer
            usually shares that upstream.
          '';
        };

        interval = mkOption {
          type = types.ints.between 1 60;
          default = 1;
          description = "Seconds between checks.";
        };

        timeoutMs = mkOption {
          type = types.ints.between 100 10000;
          default = 500;
          description = ''
            Milliseconds to wait for an ARP or ping reply. A healthy WAN
            answers in milliseconds. The whole check (probe plus process
            start-up) must fit in `interval`, so this must leave at least
            300 ms of it free; otherwise keepalived skips overlapping runs
            and detection takes twice as long.
          '';
        };

        failures = mkOption {
          type = types.ints.between 1 100;
          default = 3;
          description = "Consecutive failed checks before this node yields.";
        };

        startupGraceSec = mkOption {
          type = types.ints.unsigned;
          default = 30;
          description = ''
            Seconds after becoming master before checks count, so DHCP can
            finish on the freshly raised WAN.
          '';
        };

        retryAfterSec = mkOption {
          type = types.nullOr types.ints.positive;
          default = 900;
          description = ''
            Seconds after a yield before the pin is lifted. The node can then
            preempt again (after `preemptDelay`) and re-test its WAN; if it is
            still bad it yields again. A backup's WAN is down, so this is the
            only way it can notice a repair. During an ISP outage that affects
            both nodes, each retry moves the VIP twice. `null` never lifts the
            pin; restart keepalived to clear it.
          '';
        };
      };
    };

    transitionScripts = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      readOnly = true;
      description = "Scripts the notify FIFO reader runs per VRRP state (for checks).";
    };

    keaSync = {
      enable = mkOption {
        type = types.bool;
        default = false;
        visible = false;
        description = ''
          Deprecated and has no effect. It only opened TCP 8000 on every
          interface. Use `services.router-kea.dhcp4.ha`, which configures Kea
          HA and opens the port to the peer only.
        '';
      };
      peerAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        visible = false;
        description = "Deprecated and has no effect. See `services.router-kea.dhcp4.ha.peerAddress`.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          # WHY: keepalived skips an address it cannot parse and falls back
          # to multicast when no peer is left, on a LAN where multicast is
          # what fails. Compare canonical forms so another spelling of the
          # VIP cannot pass.
          assertion = all (p: canonicalVrrpAddress p != null && canonicalVrrpAddress p != canonicalVrrpAddress virtualIpAddress) cfg.unicastPeers;
          message = "services.router-ha.unicastPeers: list the peer's own address on vrrpInterface as a valid ${if virtualIpIsIpv6 then "IPv6" else "IPv4"} address (the VIP's family, ${cfg.virtualIp}), without a prefix length, and not the VIP.";
        }
        {
          assertion = cfg.unicastSrcIp == null || (cfg.unicastPeers != [ ] && canonicalVrrpAddress cfg.unicastSrcIp != null && canonicalVrrpAddress cfg.unicastSrcIp != canonicalVrrpAddress virtualIpAddress);
          message = "services.router-ha.unicastSrcIp needs unicastPeers and this node's own address on vrrpInterface (valid, the VIP's family, no prefix length, not the VIP).";
        }
        {
          # WHY: with an IPv6 VIP keepalived binds its receive socket to a
          # link-local source by default, so adverts the peer sends to this
          # node's global or ULA address never arrive and both become MASTER.
          assertion = !(virtualIpIsIpv6 && cfg.unicastPeers != [ ] && cfg.unicastSrcIp == null);
          message = "services.router-ha.unicastPeers with an IPv6 VIP needs unicastSrcIp: this node's address on vrrpInterface that the peer lists in its unicastPeers.";
        }
        {
          assertion =
            !cts.enable
            || (
              let
                v4 = a: builtins.match "(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})" a != null;
              in
              v4 cts.localAddress && v4 cts.peerAddress && cts.localAddress != cts.peerAddress
            );
          message = "services.router-ha.conntrackSync needs distinct IPv4 localAddress and peerAddress (no prefix length) on the sync interface.";
        }
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
        {
          # WHY: keepalived never lowers address-owner priority 255, so the
          # pin would not hold and a node with a dead WAN would preempt back.
          assertion = !wanHealthEnabled || cfg.priority < 255;
          message = "services.router-ha.wan.healthCheck needs priority below 255; keepalived does not lower address-owner priority, so the WAN pin could not hold.";
        }
        {
          # WHY: with 800 ms of a 1 s interval the script's own start-up
          # overran on a loaded host; keepalived then skipped every other
          # run and a 3-failure yield took ~6 s instead of ~3 s.
          assertion = !wanHealthEnabled || hc.timeoutMs + 300 <= hc.interval * 1000;
          message = "services.router-ha.wan.healthCheck.timeoutMs must leave at least 300 ms of interval free (timeoutMs <= interval*1000 - 300).";
        }
        {
          # WHY: a backup advertising itself as default router black-holes
          # IPv6 for the clients that pick it, since its WAN is down.
          assertion = raSenders == [ ] || ra.mode == "both-nodes";
          message =
            if ra.mode == "vrrp-owner" then
              "services.router-ha.routerAdvertisements: networks ${concatStringsSep ", " raSenders} send RAs but are not in routerAdvertisements.networks."
            else
              ''
                services.router-ha: networks ${concatStringsSep ", " raSenders} send IPv6 Router
                Advertisements on both nodes. Set services.router-ha.routerAdvertisements.mode
                to "vrrp-owner" (only the MASTER advertises) or "both-nodes".
              '';
        }
        {
          # WHY: anything else lets networkd delete the VIP on reconfigure.
          assertion = cfg.vrrpNetwork == null || elem (vrrpNet.networkConfig.KeepConfiguration or "static") [ "static" "yes" true ];
          message = "services.router-ha: ${toString cfg.vrrpNetwork} sets KeepConfiguration=${toString (vrrpNet.networkConfig.KeepConfiguration or "")}; the VRRP network needs \"static\" or \"yes\" so networkd keeps the VIP.";
        }
        {
          # WHY: anything else lets the MASTER's reload delete the address.
          assertion = !raOwner || vll == null || badKeepRaNetworks == [ ];
          message = "services.router-ha.routerAdvertisements.virtualLinkLocal: ${concatStringsSep ", " badKeepRaNetworks} set KeepConfiguration to something other than \"static\" or \"yes\"; networkd would delete the virtual link-local on reload.";
        }
        {
          assertion = !raOwner || vll == null || unresolvedRaNetworks == [ ];
          message = "services.router-ha.routerAdvertisements.virtualLinkLocal needs each network's interface; ${concatStringsSep ", " unresolvedRaNetworks} match no single interface name (set matchConfig.Name to one interface, or virtualLinkLocal = null).";
        }
        {
          assertion = !raOwner || all (n: elem n ra.networks) (attrNames ra.masterRouterLifetimeSec);
          message = "services.router-ha.routerAdvertisements.masterRouterLifetimeSec names networks that are not in routerAdvertisements.networks.";
        }
        {
          assertion = cfg.vrrpNetwork == null || (vrrpNet.matchConfig.Name or null) == cfg.vrrpInterface;
          message = "services.router-ha.vrrpNetwork \"${toString cfg.vrrpNetwork}\" must name the systemd.network.networks attribute whose matchConfig.Name is ${cfg.vrrpInterface}.";
        }
        {
          # WHY: the RA drop-in reconfigures links; without KeepConfiguration
          # the MASTER would delete its own VIP and flap.
          assertion = !raOwner || cfg.vrrpNetwork != null;
          message = "services.router-ha.routerAdvertisements.mode = \"vrrp-owner\" needs services.router-ha.vrrpNetwork (none detected for ${cfg.vrrpInterface}).";
        }
        {
          assertion = !raOwner || (ra.networks != [ ] && unknownRaNetworks == [ ] && silentRaNetworks == [ ]);
          message =
            if ra.networks == [ ] then
              "services.router-ha.routerAdvertisements.mode = \"vrrp-owner\" needs at least one network in routerAdvertisements.networks."
            else if unknownRaNetworks != [ ] then
              "services.router-ha.routerAdvertisements.networks names unknown systemd-networkd networks: ${concatStringsSep ", " unknownRaNetworks}."
            else
              "services.router-ha.routerAdvertisements.networks ${concatStringsSep ", " silentRaNetworks} do not send RAs (IPv6SendRA); remove them from the list.";
        }
        {
          # WHY: Kea HA needs both servers running; stopping the backup's Kea
          # on every VRRP transition would force partner-down on the master.
          assertion = keaHaEnabled -> !(elem "kea-dhcp4-server.service" cfg.singleActiveUnits || elem "kea-dhcp4-server" cfg.singleActiveUnits);
          message = ''
            services.router-ha: kea-dhcp4-server is in singleActiveUnits while
            services.router-kea.dhcp4.ha is enabled. Kea HA runs on both nodes;
            choose one DHCP model (see docs/router-dhcp-single-active.md).
          '';
        }
      ];

      warnings =
        optional (cfg.vrrpPassword != null)
          "services.router-ha.vrrpPassword puts the VRRP password in the Nix store; use vrrpPasswordFile instead."
        ++ optional (cfg.keaSync.enable || cfg.keaSync.peerAddress != null) ''
          services.router-ha.keaSync is deprecated and has no effect. It used to
          open TCP 8000 on every interface. Configure services.router-kea.dhcp4.ha
          instead; it opens the HA port to the peer only.
        '';

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

      services.router-ha.transitionScripts = {
        master = notifyMasterScript;
        backup = notifyBackupScript;
        fault = notifyFaultScript;
        stop = keepalivedStopScript;
        reader = notifyFifoReader;
      };

      # Keepalived for VRRP
      services.keepalived = {
        enable = true;
        enableScriptSecurity = true;
        extraGlobalDefs = ''
          script_user root
          ${optionalString hasNotifyHooks ''
            vrrp_notify_fifo ${notifyFifo}
            vrrp_notify_fifo_script "${notifyFifoReader}"
            # WHY: a reload replaces the reader and can drop a queued event;
            # replaying the current state lets the new reader re-apply it.
            fifo_write_vrrp_states_on_reload
          ''}
        '';
        vrrpInstances.main = {
          # INVARIANT: with preemptDelay every node starts BACKUP; keepalived
          # ignores preempt_delay on a MASTER-start instance.
          state = if cfg.role == "master" && cfg.preemptDelay == null then "MASTER" else "BACKUP";
          interface = cfg.vrrpInterface;
          virtualRouterId = cfg.vrrpId;
          priority = cfg.priority;
          # WHY: docs/router-ha-pair-guide.md#unicast-peers (LANs that drop VRRP multicast).
          inherit (cfg) unicastPeers unicastSrcIp;
          virtualIps = [
            { addr = cfg.virtualIp; }
          ];
          trackScripts = optionals wanHealthEnabled [
            "router_ha_wan_health"
            "router_ha_wan_pin"
          ];
          extraConfig = ''
            ${optionalString (cfg.preemptDelay != null) "preempt_delay ${toString cfg.preemptDelay}"}
            ${garpConfig}
            authentication {
              auth_type PASS
              auth_pass "${if usePasswordFile then "$ROUTER_HA_VRRP_PASS" else cfg.vrrpPassword}"
            }
          '';
        };
      };

      services.keepalived.vrrpScripts = mkIf wanHealthEnabled {
        router_ha_wan_health = {
          script = "${wanHealthScript}";
          inherit (hc) interval;
          # The script counts failures itself; keepalived acts on each result.
          timeout = hc.interval + 5;
          fall = 1;
          rise = 1;
          user = "root";
        };
        # GOTCHA: a track_file would react faster, but the nixpkgs module
        # renders extraConfig after the instances, and keepalived ignores a
        # track_file referenced before it is declared.
        router_ha_wan_pin = {
          script = "${pkgs.writeShellScript "router-ha-wan-pin" ''
            [ "$(${pkgs.coreutils}/bin/cat ${escapeShellArg wanPenaltyFile} 2>/dev/null)" != 1 ]
          ''}";
          interval = 1;
          weight = -253;
          fall = 1;
          rise = 1;
          user = "root";
        };
      };

      # INVARIANT: a keepalived (re)start clears the pin, so a restart is a
      # fresh start and the manual way to lift it early.
      systemd.services.keepalived.serviceConfig.ExecStartPre = mkIf wanHealthEnabled (mkBefore [
        "+${pkgs.coreutils}/bin/rm -f ${wanPenaltyFile} ${wanFailCountFile}"
      ]);

      systemd.services.keepalived.serviceConfig.ExecStopPost = [
        "+${keepalivedStopScript}"
      ];
    }

    (mkIf (cfg.peerWaitSec > 0) {
      systemd.services.keepalived.serviceConfig = {
        ExecStartPre = mkAfter [ "+${peerWaitScript}" ];
        TimeoutStartSec = mkDefault (max 90 (cfg.peerWaitSec + 30));
      };
    })

    (mkIf (raOwner && vll != null) {
      # WHY: the drop-in's reload must not delete the virtual link-local
      # (a foreign address) on the MASTER.
      systemd.network.networks = genAttrs ra.networks (_: {
        networkConfig.KeepConfiguration = mkDefault "static";
      });
    })

    (mkIf (cfg.vrrpNetwork != null) {
      # WHY: keeps keepalived's VIP (a permanent foreign address) across
      # networkd reconfigures and restarts; see the vrrpNetwork option.
      systemd.network.networks.${cfg.vrrpNetwork}.networkConfig.KeepConfiguration = mkDefault "static";
    })

    (mkIf raOwner {
      systemd.network.networks = genAttrs ra.networks (_: {
        ipv6SendRAConfig.RouterLifetimeSec = mkForce 0;
      });

      services.router-ha.singleActiveUnits = [ raOwnerUnit ];

      # Started by router-ha on MASTER, stopped on BACKUP/FAULT.
      systemd.services.router-ha-ra-owner = {
        description = "IPv6 Router Advertisements for the VRRP MASTER";
        after = [ "systemd-networkd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = raOwnerScript true;
          ExecStop = raOwnerScript false;
        };
      };
    })

    (mkIf cts.enable {
      environment.systemPackages = [ cts.package ];
      # conntrackd's default path, so `conntrackd -s`, `-i` and `-e` work by hand.
      environment.etc."conntrackd/conntrackd.conf".source = conntrackdConf;

      systemd.services.conntrackd = {
        description = "conntrackd connection-state sync with the VRRP peer";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        before = [ "keepalived.service" ];
        serviceConfig = {
          ExecStart = "${cts.package}/bin/conntrackd -C ${conntrackdConf}";
          RuntimeDirectory = "conntrackd";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
      # WHY: keepalived's MASTER transition commits through conntrackd's socket.
      systemd.services.keepalived.wants = [ "conntrackd.service" ];
      systemd.services.keepalived.after = [ "conntrackd.service" ];
    })

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

    (mkIf cfg.wan.enable (
      let
        wanNet = if cfg.wan.network == null then { } else config.systemd.network.networks.${cfg.wan.network} or { };
        matchName = wanNet.matchConfig.Name or null;
        # GOTCHA: router-ha's own ActivationPolicy assignment creates the
        # entry, so existence proves nothing; require it to match the WAN.
        matchesWan =
          if isList matchName then elem cfg.wan.interface matchName
          else if isString matchName then elem cfg.wan.interface (splitString " " matchName)
          else false;
        networkMac = wanNet.linkConfig.MACAddress or null;
      in
      {
        assertions = [
          {
            assertion = matchesWan;
            message = "services.router-ha.wan: set wan.network to the systemd.network.networks attribute whose matchConfig.Name is ${cfg.wan.interface}, so router-ha can give it ActivationPolicy=manual (${if cfg.wan.network == null then "none detected" else "\"${cfg.wan.network}\" does not match ${cfg.wan.interface}"}).";
          }
          {
            # WHY: networkctl reconfigure re-applies [Link] MACAddress, which
            # would undo the cloned MAC before DHCP starts.
            assertion = cfg.wan.clonedMac == null || networkMac == null || networkMac == cfg.wan.clonedMac;
            message = "services.router-ha.wan: network \"${toString cfg.wan.network}\" sets MACAddress=${toString networkMac}, which overrides clonedMac ${toString cfg.wan.clonedMac} on promotion. Remove it (e.g. router-networking wan.macAddress) or make them equal.";
          }
        ];
      }
    ))
    (mkIf (cfg.wan.enable && cfg.wan.sharedDhcpIdentity) {
      assertions = [
        {
          assertion = cfg.wan.clonedMac != null && builtins.match "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}" cfg.wan.clonedMac != null;
          message = "services.router-ha.wan.sharedDhcpIdentity derives the DUID from wan.clonedMac, which must be set to a MAC such as 02:00:00:00:00:01.";
        }
      ];
    })
    (mkIf (cfg.wan.enable && cfg.wan.sharedDhcpIdentity && cfg.wan.clonedMac != null && cfg.wan.network != null) (
      let
        mac = toLower cfg.wan.clonedMac;
        # DUID-LL (RFC 8415 11.4): hardware type 1 (Ethernet), then the MAC.
        # WHY: explicit raw data, not the link's current address, so the
        # DUID cannot depend on whether the clone was applied yet.
        identity = {
          DUIDType = mkDefault "link-layer";
          DUIDRawData = mkDefault "00:01:${mac}";
          # INVARIANT: same on both nodes; the default IAID hashes the
          # interface name, which can differ between the two machines.
          IAID = mkDefault (fromHexString (concatStrings (drop 2 (splitString ":" mac))));
        };
      in
      {
        systemd.network.networks.${cfg.wan.network} = {
          dhcpV4Config = identity;
          dhcpV6Config = identity;
        };
      }
    ))
    (mkIf (cfg.wan.enable && cfg.wan.network != null) {
      # INVARIANT: manual, not always-down: networkctl up/reconfigure are
      # refused for always-down links, and "up" would re-raise the WAN on
      # the standby whenever networkd restarts.
      systemd.network.networks.${cfg.wan.network} = {
        linkConfig.ActivationPolicy = "manual";
        # WHY: networkd restarts the DHCP clients whenever it reconfigures an
        # up link (a deploy changing this .network does). With SendRelease
        # they release the lease first, and an ISP may then hand out a new
        # address or /56 (docs/router-ha-prior-art.md#adopted-from-this-review).
        dhcpV4Config.SendRelease = mkDefault false;
        dhcpV6Config.SendRelease = mkDefault false;
      };
    })
    (mkIf (cfg.wan.enable && cfg.wan.network != null && cfg.wan.clonedMac != null) {
      # WHY: on a planned handover the old master still holds the cloned
      # MAC's link-local address for a moment. DAD on the new master then
      # marks fe80::...:<mac> dadfailed for good, and DHCPv6/PD never start
      # (seen in vm-router-ha-wan-failover). VRRP already makes the clone
      # exclusive, so duplicate detection only adds that failure.
      systemd.network.networks.${cfg.wan.network}.networkConfig.IPv6DuplicateAddressDetection = mkDefault 0;
      warnings =
        let
          dad = config.systemd.network.networks.${cfg.wan.network}.networkConfig.IPv6DuplicateAddressDetection or 0;
        in
        optional (dad != 0) ''
          services.router-ha.wan: network "${cfg.wan.network}" sets
          IPv6DuplicateAddressDetection=${toString dad} on the cloned-MAC WAN.
          On a planned handover the new master can then mark the shared
          link-local address dadfailed, and DHCPv6/PD never start.
        '';
    })

    # Firewall integration
    (if hasRouterFirewall then {
      services.router-firewall = mkIf (config.services.router-firewall.enable or false) {
        # VRRP is IP protocol 112 (multicast, or unicast with unicastPeers)
        extraInputRules = ''
          meta l4proto vrrp accept comment "Allow VRRP traffic"
        '' + optionalString cts.enable ''
          iifname "${cts.interface}" ip saddr ${cts.peerAddress} udp dport ${toString cts.port} accept comment "Allow conntrackd sync from the VRRP peer"
        '';
      };
    } else { })
  ]);
}
