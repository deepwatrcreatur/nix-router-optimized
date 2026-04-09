# Router web dashboard with real-time traffic monitoring
# Enhanced version with Chart.js graphs and modular widgets
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-dashboard;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };

  normalizeRole = role:
    if role == "management" then
      "mgmt"
    else
      role;

  effectiveInterfaces =
    if cfg.interfaces != [ ] || !cfg.autoInterfacesFromOptimizations then
      cfg.interfaces
    else
      mapAttrsToList (_name: iface: {
        device = iface.device;
        label = iface.label;
        role = normalizeRole iface.role;
      }) optimizationInterfaces;

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
        }) effectiveInterfaces)},
        links: ${builtins.toJSON (map (link: {
          label = link.label;
          kind = link.kind;
          url = link.url;
          copyText = link.copyText;
          icon = link.icon;
        }) cfg.links)},
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

    autoInterfacesFromOptimizations = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, derive dashboard interfaces from
        services.router-optimizations.interfaces if no explicit interface list
        is set here.
      '';
    };

    links = mkOption {
      type = types.listOf (types.submodule {
        options = {
          label = mkOption {
            type = types.str;
            description = "Link button label";
          };
          kind = mkOption {
            type = types.enum [ "link" "copy" ];
            default = "link";
            description = "Whether the quick link opens a URL or copies text to the clipboard.";
          };
          url = mkOption {
            type = types.str;
            default = "";
            description = "URL to link to";
          };
          copyText = mkOption {
            type = types.str;
            default = "";
            description = "Text copied to the clipboard when kind = copy.";
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
    users.users.router-dashboard = {
      isSystemUser = true;
      group = "router-dashboard";
      description = "Router dashboard service user";
      extraGroups = [ "systemd-journal" ];
    };

    users.groups.router-dashboard = { };

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
        DASHBOARD_INTERFACES = builtins.toJSON (map (iface: {
          device = iface.device;
          label = iface.label;
          role = iface.role;
        }) effectiveInterfaces);
        DASHBOARD_SERVICES = builtins.toJSON cfg.services;
        DASHBOARD_WOL_DEVICES = builtins.toJSON cfg.wakeOnLan.devices;
        TECHNITIUM_URL = "http://localhost:5380";
        TECHNITIUM_API_KEY_FILE = if config ? age && config.age ? secrets && config.age.secrets ? technitium-api-key
          then config.age.secrets.technitium-api-key.path
          else "";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${apiServer}";
        Restart = "always";
        RestartSec = "5s";

        User = "router-dashboard";
        Group = "router-dashboard";

        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        # PrivateUsers omitted: conflicts with AmbientCapabilities on non-root users.
        # The dedicated service user + CapabilityBoundingSet already provide isolation.

        # Network capabilities: CAP_NET_ADMIN for interface stats, CAP_NET_RAW for ping
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];

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

    # Allow the dashboard service user to run fail2ban-client status (read-only) without password
    security.sudo.extraConfig = ''
      router-dashboard ALL=(ALL) NOPASSWD: ${pkgs.fail2ban}/bin/fail2ban-client status
      router-dashboard ALL=(ALL) NOPASSWD: ${pkgs.fail2ban}/bin/fail2ban-client status *
    '';

    # Allow dashboard port in NixOS firewall when it is active.
    # NOTE: when router-firewall is enabled instead, add the dashboard port via:
    #   services.router-firewall.trustedTcpPorts = [ cfg.port ];
    networking.firewall.allowedTCPPorts = mkIf config.networking.firewall.enable [ cfg.port ];

    # Auto-open dashboard port in router-firewall when both are enabled
    services.router-firewall.trustedTcpPorts = mkIf (config.services.router-firewall.enable or false) [ cfg.port ];
  };
}
