# Router performance optimizations inspired by RouterOS
# Includes fasttrack, hardware offload, queue management
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-optimizations;
in {
  options.services.router-optimizations = {
    enable = mkEnableOption "router performance optimizations";
    
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
  };

  config = mkIf cfg.enable {
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
      };
      
      script = ''
        # Function to configure interface
        configure_interface() {
          local iface=$1
          local role=$2
          local bandwidth=$3
          
          # Check if interface exists
          if ! ${pkgs.iproute2}/bin/ip link show $iface &>/dev/null; then
            echo "Interface $iface not found, skipping..."
            return
          fi
          
          # Enable hardware offloads
          ${pkgs.ethtool}/bin/ethtool -K $iface tso on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface gso on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface gro on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface ufo on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface lro on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface sg on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface tx on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -K $iface rx on 2>/dev/null || true
          
          # Increase ring buffer sizes for better performance
          ${pkgs.ethtool}/bin/ethtool -G $iface rx 4096 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -G $iface tx 4096 2>/dev/null || true
          
          # Enable interrupt coalescing
          ${pkgs.ethtool}/bin/ethtool -C $iface adaptive-rx on 2>/dev/null || true
          ${pkgs.ethtool}/bin/ethtool -C $iface adaptive-tx on 2>/dev/null || true
          
          # Configure queue discipline
          if [ "$role" = "wan" ] && [ -n "$bandwidth" ]; then
            # WAN interface: use CAKE for better bufferbloat control
            ${pkgs.iproute2}/bin/tc qdisc replace dev $iface root cake bandwidth $bandwidth
          else
            # Non-WAN interfaces: use fq_codel for internal traffic
            ${pkgs.iproute2}/bin/tc qdisc replace dev $iface root fq_codel
          fi
          
          echo "Configured $iface (Role: $role)"
        }
        
        # Wait for interfaces to be available
        sleep 2
        
        ${concatStringsSep "\n" (mapAttrsToList (name: iface: ''
          configure_interface ${iface.device} ${iface.role} ${if iface.bandwidth != null then iface.bandwidth else ""}
        '') cfg.interfaces)}
        
        echo "Router hardware offload configuration complete"
      '';
    };

    # XDP packet filtering placeholder
    systemd.services.xdp-firewall = {
      description = "XDP-based early packet filtering";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Placeholder for XDP programs
        # XDP can drop packets at the NIC level before they reach the kernel
        echo "XDP firewall ready (custom programs can be added)"
      '';
    };
  };
}
