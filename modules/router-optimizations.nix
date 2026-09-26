# Router performance optimizations inspired by RouterOS
# Includes fasttrack, hardware offload, queue management
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-optimizations;

  offloadConfig = builtins.toJSON {
    profile = cfg.profile;
    interfaces = mapAttrsToList (name: iface: {
      device = iface.device;
      role = iface.role;
      label = iface.label;
      bandwidth = iface.bandwidth;
      profile = if iface.offloadProfile != null then iface.offloadProfile else cfg.profile;
    }) cfg.interfaces;
  };

  offloadConfigFile = pkgs.writeText "router-offload-config.json" offloadConfig;

  offloadScript = pkgs.writeScriptBin "router-offload-negotiate" ''
    #!${pkgs.python3}/bin/python3
    import json
    import os
    import re
    import subprocess
    import sys
    from datetime import datetime, timezone

    with open("${offloadConfigFile}") as f:
        CONFIG = json.load(f)

    ETHTOOL = "${pkgs.ethtool}/bin/ethtool"
    IP = "${pkgs.iproute2}/bin/ip"
    TC = "${pkgs.iproute2}/bin/tc"

    def run_cmd(cmd):
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            return res.returncode, res.stdout, res.stderr
        except Exception as e:
            return -1, "", str(e)

    FEATURE_MAP = {
        "rx": "rx-checksumming",
        "tx": "tx-checksumming",
        "sg": "scatter-gather",
        "tso": "tcp-segmentation-offload",
        "gso": "generic-segmentation-offload",
        "gro": "generic-receive-offload",
        "lro": "large-receive-offload",
        "rx-udp-gro-forwarding": "rx-udp-gro-forwarding",
        "rx-gro-list": "rx-gro-list",
    }

    def parse_ethtool_features(output):
        features = {}
        for line in output.splitlines():
            line = line.strip()
            if not line or ":" not in line:
                continue
            parts = line.split(":", 1)
            feat_name = parts[0].strip()
            val_part = parts[1].strip()
            val_tokens = val_part.split()
            if not val_tokens:
                continue
            state = val_tokens[0].lower()
            is_fixed = "[fixed]" in val_part
            features[feat_name] = {
                "state": state,
                "fixed": is_fixed
            }
        return features

    def parse_ring_buffer(output):
        rx_max, tx_max = None, None
        rx_cur, tx_cur = None, None
        in_preset = False
        in_current = False
        for line in output.splitlines():
            line = line.strip()
            if "Pre-set maximums:" in line:
                in_preset = True
                in_current = False
                continue
            elif "Current hardware settings:" in line:
                in_preset = False
                in_current = True
                continue
            
            m_rx = re.match(r"^RX:\s*(\d+)", line)
            m_tx = re.match(r"^TX:\s*(\d+)", line)
            if in_preset:
                if m_rx: rx_max = int(m_rx.group(1))
                if m_tx: tx_max = int(m_tx.group(1))
            elif in_current:
                if m_rx: rx_cur = int(m_rx.group(1))
                if m_tx: tx_cur = int(m_tx.group(1))
                
        return {
            "rx_max": rx_max,
            "tx_max": tx_max,
            "rx_current": rx_cur,
            "tx_current": tx_cur,
        }

    def parse_coalesce(output):
        adaptive_rx = False
        adaptive_tx = False
        m = re.search(r"Adaptive RX:\s*(on|off)\s+TX:\s*(on|off)", output, re.IGNORECASE)
        if m:
            adaptive_rx = (m.group(1).lower() == "on")
            adaptive_tx = (m.group(2).lower() == "on")
        return {
            "adaptive_rx": adaptive_rx,
            "adaptive_tx": adaptive_tx,
        }

    def get_driver(iface):
        rc, out, _ = run_cmd([ETHTOOL, "-i", iface])
        if rc == 0:
            for line in out.splitlines():
                if line.startswith("driver:"):
                    return line.split(":", 1)[1].strip()
        return "unknown"

    def configure_interface(if_cfg):
        dev = if_cfg["device"]
        role = if_cfg.get("role", "opt")
        bandwidth = if_cfg.get("bandwidth")
        prof = if_cfg.get("profile", CONFIG.get("profile", "generic"))
        
        rc, _, _ = run_cmd([IP, "link", "show", dev])
        if rc != 0:
            print(f"Interface {dev} not found, skipping...")
            return None

        driver = get_driver(dev)
        print(f"Configuring {dev} (Driver: {driver}, Role: {role}, Profile: {prof})...")

        # Invariant: LRO is ALWAYS OFF for a routing interface
        if prof == "intel-baremetal":
            targets = {
                "lro": "off",
                "gro": "on",
                "rx-udp-gro-forwarding": "on",
                "rx-gro-list": "off",
                "tso": "on",
                "gso": "on",
                "sg": "on",
                "tx": "on",
                "rx": "on",
            }
            target_ring = 4096
            want_adaptive = True
        elif prof == "realtek-baremetal":
            targets = {
                "lro": "off",
                "gro": "on",
                "rx-udp-gro-forwarding": "off",
                "rx-gro-list": "off",
                "tso": "off",
                "gso": "off",
                "sg": "on",
                "tx": "on",
                "rx": "on",
            }
            target_ring = None
            want_adaptive = True
        elif prof == "virtio-vm":
            targets = {
                "lro": "off",
                "gro": "on",
                "rx-udp-gro-forwarding": "on",
                "rx-gro-list": "off",
            }
            target_ring = None
            want_adaptive = False
        else:
            targets = {
                "lro": "off",
                "gro": "on",
                "rx-udp-gro-forwarding": "on",
                "rx-gro-list": "off",
                "tso": "on",
                "gso": "on",
                "sg": "on",
                "tx": "on",
                "rx": "on",
            }
            target_ring = 4096
            want_adaptive = True

        rc, out, _ = run_cmd([ETHTOOL, "-k", dev])
        current_features = parse_ethtool_features(out) if rc == 0 else {}

        offload_status = {}

        for short_name, req_state in targets.items():
            ethtool_name = FEATURE_MAP.get(short_name, short_name)
            feat_info = current_features.get(ethtool_name)

            if not feat_info:
                rc_set, _, err = run_cmd([ETHTOOL, "-K", dev, short_name, req_state])
                if rc_set == 0:
                    offload_status[short_name] = {
                        "requested": req_state,
                        "supported": True,
                        "enabled": (req_state == "on"),
                        "effective": req_state,
                        "reason_disabled": None if req_state == "on" else "disabled by policy"
                    }
                else:
                    offload_status[short_name] = {
                        "requested": req_state,
                        "supported": False,
                        "enabled": False,
                        "effective": "unknown",
                        "reason_disabled": f"rejected by driver: {err.strip()}"
                    }
                continue

            cur_state = feat_info["state"]
            is_fixed = feat_info["fixed"]

            if cur_state == req_state:
                offload_status[short_name] = {
                    "requested": req_state,
                    "supported": True,
                    "enabled": (cur_state == "on"),
                    "effective": cur_state,
                    "reason_disabled": None if cur_state == "on" else "disabled by policy"
                }
            else:
                if is_fixed:
                    offload_status[short_name] = {
                        "requested": req_state,
                        "supported": False,
                        "enabled": (cur_state == "on"),
                        "effective": cur_state,
                        "reason_disabled": "fixed by driver"
                    }
                else:
                    rc_set, _, err = run_cmd([ETHTOOL, "-K", dev, short_name, req_state])
                    if rc_set == 0:
                        offload_status[short_name] = {
                            "requested": req_state,
                            "supported": True,
                            "enabled": (req_state == "on"),
                            "effective": req_state,
                            "reason_disabled": None if req_state == "on" else "disabled by policy"
                        }
                    else:
                        offload_status[short_name] = {
                            "requested": req_state,
                            "supported": False,
                            "enabled": (cur_state == "on"),
                            "effective": cur_state,
                            "reason_disabled": f"rejected by driver: {err.strip()}"
                        }

        rc_g, out_g, _ = run_cmd([ETHTOOL, "-g", dev])
        ring_info = parse_ring_buffer(out_g) if rc_g == 0 else {"rx_max": None, "tx_max": None, "rx_current": None, "tx_current": None}

        if target_ring and ring_info["rx_max"] and ring_info["tx_max"]:
            new_rx = min(target_ring, ring_info["rx_max"])
            new_tx = min(target_ring, ring_info["tx_max"])
            if new_rx != ring_info["rx_current"] or new_tx != ring_info["tx_current"]:
                rc_set, _, _ = run_cmd([ETHTOOL, "-G", dev, "rx", str(new_rx), "tx", str(new_tx)])
                if rc_set == 0:
                    ring_info["rx_current"] = new_rx
                    ring_info["tx_current"] = new_tx

        rc_c, out_c, _ = run_cmd([ETHTOOL, "-c", dev])
        coalesce_info = parse_coalesce(out_c) if rc_c == 0 else {"adaptive_rx": False, "adaptive_tx": False}

        if want_adaptive:
            rc_set, _, _ = run_cmd([ETHTOOL, "-C", dev, "adaptive-rx", "on", "adaptive-tx", "on"])
            if rc_set == 0:
                coalesce_info["adaptive_rx"] = True
                coalesce_info["adaptive_tx"] = True

        if role == "wan" and bandwidth:
            qdisc_cmd = [TC, "qdisc", "replace", "dev", dev, "root", "cake", "bandwidth", bandwidth]
            qdisc_name = f"cake bandwidth {bandwidth}"
        else:
            qdisc_cmd = [TC, "qdisc", "replace", "dev", dev, "root", "fq_codel"]
            qdisc_name = "fq_codel"

        run_cmd(qdisc_cmd)

        return {
            "role": role,
            "driver": driver,
            "effective_profile": prof,
            "offloads": offload_status,
            "ring_buffer": ring_info,
            "coalescing": coalesce_info,
            "qdisc": qdisc_name,
        }

    def main():
        os.makedirs("/run/router", exist_ok=True)
        report = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "global_profile": CONFIG.get("profile", "generic"),
            "interfaces": {}
        }

        for if_cfg in CONFIG.get("interfaces", []):
            dev = if_cfg["device"]
            res = configure_interface(if_cfg)
            if res is not None:
                report["interfaces"][dev] = res

        tmp_path = "/run/router/nic-offload-status.json.tmp"
        final_path = "/run/router/nic-offload-status.json"
        with open(tmp_path, "w") as f:
            json.dump(report, f, indent=2)
        os.replace(tmp_path, final_path)
        print("Router hardware offload configuration complete. Saved status to /run/router/nic-offload-status.json")

    if __name__ == "__main__":
        main()
  '';
in {
  options.services.router-optimizations = {
    enable = mkEnableOption "router performance optimizations";

    profile = mkOption {
      type = types.enum [ "intel-baremetal" "realtek-baremetal" "virtio-vm" "generic" ];
      default = "generic";
      description = ''
        Hardware optimization preset profile.
        - intel-baremetal: Aggressive hardware offloads (TSO/GSO/GRO, ring buffer 4096, adaptive coalescing).
        - realtek-baremetal: Conservative offloads (GRO on, LRO off, TSO/GSO disabled to prevent r8169 TX hangs).
        - virtio-vm: Virtualized guest profile (GRO on, LRO off, hypervisor-managed ring buffers and segmentation).
        - generic: Standard balanced offloads for general hardware.
      '';
    };
    
    interfaces = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          device = mkOption {
            type = types.str;
            description = "Physical device name (e.g., ens18, eth0)";
          };
          
          role = mkOption {
            type = types.enum [ "wan" "lan" "opt" "management" ];
            default = "opt";
            description = "Interface role (wan, lan, opt, management)";
          };
          
          label = mkOption {
            type = types.str;
            description = "Human-readable label for dashboard (e.g., 'WAN', 'LAN', 'OPT1', 'Management')";
          };
          
          bandwidth = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Bandwidth limit for CAKE QoS (e.g., '100Mbit', '1Gbit'). Only applies to WAN interfaces.";
          };

          offloadProfile = mkOption {
            type = types.nullOr (types.enum [ "intel-baremetal" "realtek-baremetal" "virtio-vm" "generic" ]);
            default = null;
            description = "Per-interface hardware offload profile override. If null, inherits global profile.";
          };
        };
      });
      default = {};
      description = ''
        Interface configurations. Each interface can have an arbitrary label.
        Example:
        {
          wan = { device = "ens17"; role = "wan"; label = "WAN"; bandwidth = "1Gbit"; };
          lan = { device = "ens16"; role = "lan"; label = "LAN"; };
          mgmt = { device = "ens18"; role = "management"; label = "Management"; };
          opt1 = { device = "ens19"; role = "opt"; label = "OPT1"; };
        }
      '';
    };
    
    conntrack-max = mkOption {
      type = types.int;
      default = 262144;
      description = "Maximum number of connection tracking entries";
    };

    conntrack-hashsize = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = ''
        Hash table size for the conntrack module. Defaults to conntrack-max / 4.
        Larger values reduce hash chain length and improve lookup performance at
        the cost of memory (~8 bytes per bucket). Set via the nf_conntrack kernel
        module parameter, which must be configured before the module loads.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.hello; # Placeholder, should be overridden in flake or host
      description = "The router-diag package to install.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.conntrack-hashsize == null || cfg.conntrack-hashsize <= cfg.conntrack-max;
        message = "router-optimizations.conntrack-hashsize must not exceed conntrack-max (${toString cfg.conntrack-max}).";
      }
    ];

    # Set conntrack hash table size via module parameter (must be set before module loads)
    boot.extraModprobeConfig = let
      hashsize = if cfg.conntrack-hashsize != null then cfg.conntrack-hashsize else cfg.conntrack-max / 4;
    in "options nf_conntrack hashsize=${toString hashsize}";

    # Kernel modules for advanced networking
    boot.kernelModules = [ 
      "tcp_bbr"           # Better congestion control
      "sch_fq"            # Fair queue scheduler
      "sch_fq_codel"      # FQ-CoDel queue discipline
      "sch_cake"          # CAKE queue discipline
      "act_bpf"           # BPF actions
      "cls_bpf"           # BPF classifier
      "ifb"               # Intermediate functional block (for ingress shaping)
    ];

    # Advanced kernel network tuning
    boot.kernel.sysctl = {
      # IP forwarding
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      
      # Connection tracking optimizations (fasttrack-like)
      "net.netfilter.nf_conntrack_max" = cfg.conntrack-max;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 7200;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 30;
      "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 15;
      "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = 30;
      
      # TCP optimizations
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.ipv4.tcp_mtu_probing" = 1;
      "net.ipv4.tcp_rmem" = "4096 87380 33554432";
      "net.ipv4.tcp_wmem" = "4096 87380 33554432";
      "net.ipv4.tcp_max_syn_backlog" = 8192;
      "net.ipv4.tcp_tw_reuse" = 1;
      
      # Core socket buffer sizes
      "net.core.rmem_default" = 262144;
      "net.core.rmem_max" = 33554432;
      "net.core.wmem_default" = 262144;
      "net.core.wmem_max" = 33554432;
      "net.core.netdev_max_backlog" = 5000;
      "net.core.optmem_max" = 65536;
      
      # Reduce TIME_WAIT buckets
      "net.ipv4.tcp_max_tw_buckets" = 200000;
      
      # Enable TCP window scaling
      "net.ipv4.tcp_window_scaling" = 1;
      
      # Enable selective acknowledgements
      "net.ipv4.tcp_sack" = 1;
      
      # Increase the maximum amount of memory allocated to shm
      "kernel.shmmax" = 68719476736;
      "kernel.shmall" = 4294967296;
      
      # Disable packet filtering on bridges (if used)
      "net.bridge.bridge-nf-call-iptables" = mkDefault 0;
      "net.bridge.bridge-nf-call-ip6tables" = mkDefault 0;
      "net.bridge.bridge-nf-call-arptables" = mkDefault 0;
      
      # Increase local port range
      "net.ipv4.ip_local_port_range" = "10000 65535";
      
      # Enable ECN (Explicit Congestion Notification)
      "net.ipv4.tcp_ecn" = 1;
      
      # Protect against time-wait assassination
      "net.ipv4.tcp_rfc1337" = 1;
    };

    # Install performance monitoring and traffic control tools
    environment.systemPackages = with pkgs; [
      ethtool              # Hardware offload configuration
      iproute2             # tc (traffic control) for queue management
      tcpdump              # Packet analysis
      conntrack-tools      # Connection tracking utilities
      iperf3               # Network performance testing
      mtr                  # Network diagnostics
      bpftools             # BPF/XDP tools
      bpftrace             # Dynamic tracing
      numactl              # NUMA control
      irqbalance           # IRQ balancing for multi-core
      cfg.package          # Operational diagnostics CLI
      offloadScript        # Driver-aware offload negotiation and status tracker
    ];

    # Enable IRQ balancing for better multi-core performance
    services.irqbalance.enable = true;

    # Systemd service to enable hardware offloads and queue management
    systemd.services.router-hardware-offload = {
      description = "Enable hardware offloads and queue management for router";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${offloadScript}/bin/router-offload-negotiate";
      };
    };

  };
}
