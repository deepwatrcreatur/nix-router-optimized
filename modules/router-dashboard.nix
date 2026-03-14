# Router web dashboard with real-time traffic monitoring
# Enhanced version with Chart.js graphs and modular widgets
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-dashboard;

  # Package all dashboard static files
  dashboardStatic = pkgs.stdenv.mkDerivation {
    name = "router-dashboard-static";
    src = ./router-dashboard;

    installPhase = ''
      mkdir -p $out
      cp -r * $out/

      # Generate config.js with Nix-provided configuration
      cat > $out/js/config.js << 'EOF'
      window.DASHBOARD_CONFIG = {
        interfaces: ${builtins.toJSON (map (iface: {
          device = iface.device;
          label = iface.label;
          role = iface.role;
        }) cfg.interfaces)},
        links: ${builtins.toJSON cfg.links},
        services: ${builtins.toJSON cfg.services},
        wolDevices: ${builtins.toJSON (map (device: {
          name = device.name;
          macAddress = device.macAddress;
          broadcastAddress = device.broadcastAddress;
          port = device.port;
        }) cfg.wakeOnLan.devices)},
        refreshInterval: ${toString cfg.refreshInterval}
      };
      EOF
    '';
  };

  # API server script
  apiServer = ./router-dashboard/api/server.py;

in {
  options.services.router-dashboard = {
    enable = mkEnableOption "enhanced router web dashboard";

    port = mkOption {
      type = types.port;
      default = 8888;
      description = "Port for the router dashboard";
    };

    bind-address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "IP address to bind the dashboard to";
    };

    interfaces = mkOption {
      type = types.listOf (types.submodule {
        options = {
          device = mkOption {
            type = types.str;
            description = "Network interface device name (e.g., eth0, ens18)";
          };
          label = mkOption {
            type = types.str;
            description = "Human-readable label for the interface (e.g., WAN, LAN)";
          };
          role = mkOption {
            type = types.enum [ "wan" "lan" "opt" "mgmt" ];
            default = "opt";
            description = "Interface role: wan (external), lan (internal), opt (optional), mgmt (management)";
          };
        };
      });
      default = [];
      example = [
        { device = "ens17"; label = "WAN"; role = "wan"; }
        { device = "ens16"; label = "LAN"; role = "lan"; }
        { device = "ens18"; label = "Management"; role = "mgmt"; }
      ];
      description = "Network interfaces to monitor with labels";
    };

    links = mkOption {
      type = types.listOf (types.submodule {
        options = {
          label = mkOption {
            type = types.str;
            description = "Link button label";
          };
          url = mkOption {
            type = types.str;
            description = "URL to link to";
          };
          icon = mkOption {
            type = types.str;
            default = "";
            description = "Optional emoji icon";
          };
        };
      });
      default = [
        { label = "DNS Admin"; url = "http://gateway:5380"; icon = "🌍"; }
      ];
      description = "Quick links to display on dashboard";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "nftables"
        "caddy"
        "prometheus"
        "grafana"
        "netdata"
      ];
      description = "Systemd services to monitor";
    };

    refreshInterval = mkOption {
      type = types.int;
      default = 5;
      description = "Widget refresh interval in seconds";
    };

    theme = mkOption {
      type = types.enum [ "dark" "light" ];
      default = "dark";
      description = "Dashboard color theme";
    };

    wakeOnLan.devices = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the Wake-on-LAN target.";
          };
          macAddress = mkOption {
            type = types.str;
            description = "Target MAC address in AA:BB:CC:DD:EE:FF format.";
          };
          broadcastAddress = mkOption {
            type = types.str;
            default = "255.255.255.255";
            description = "Broadcast address used for the magic packet.";
          };
          port = mkOption {
            type = types.port;
            default = 9;
            description = "UDP port used for Wake-on-LAN magic packets.";
          };
        };
      });
      default = [];
      example = [
        {
          name = "Media Server";
          macAddress = "AA:BB:CC:DD:EE:FF";
          broadcastAddress = "10.10.10.255";
          port = 9;
        }
      ];
      description = "Devices exposed in the dashboard Wake-on-LAN widget.";
    };
  };

  config = mkIf cfg.enable {
    # Router dashboard service
    systemd.services.router-dashboard = {
      description = "Enhanced Router Dashboard HTTP Server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DASHBOARD_PORT = toString cfg.port;
        DASHBOARD_BIND = cfg.bind-address;
        DASHBOARD_STATIC = "${dashboardStatic}";
        DASHBOARD_THEME = cfg.theme;
        DASHBOARD_SERVICES = builtins.toJSON cfg.services;
        DASHBOARD_WOL_DEVICES = builtins.toJSON cfg.wakeOnLan.devices;
        TECHNITIUM_URL = "http://localhost:5380";
        TECHNITIUM_API_KEY_FILE = if config.age.secrets ? technitium-api-key
          then config.age.secrets.technitium-api-key.path
          else "";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${apiServer}";
        Restart = "always";
        RestartSec = "5s";

        # Run as dynamic user for security
        DynamicUser = true;
        SupplementaryGroups = [ "systemd-journal" ];

        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;

        # Allow reading network stats and ping
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];

        # Needed for ping to work with dynamic user
        PrivateUsers = false;

        # Read-only paths we need access to
        ReadOnlyPaths = [
          "/proc"
          "/sys/class/net"
          "/var/log/journal"
          "/run/agenix"
        ];
      };

      path = with pkgs; [
        iproute2
        procps
        conntrack-tools
        nftables
        coreutils
        systemd
        iputils  # for ping
        fail2ban
        speedtest-cli  # for speed tests
        "/run/wrappers"  # for sudo wrapper
      ];
    };

    # Allow any user to run fail2ban-client status (read-only) via sudo without password
    # This is safe since 'status' is a read-only command
    # Use the symlink path which is stable across rebuilds
    security.sudo.extraConfig = ''
      ALL ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/fail2ban-client status
      ALL ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/fail2ban-client status *
    '';

    # Allow dashboard port in firewall
    networking.firewall.allowedTCPPorts = mkIf config.networking.firewall.enable [ cfg.port ];
  };
}
