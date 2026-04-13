{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-netbird;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
  tailscaleEnabled =
    if hasRouterOption [ "services" "router-tailscale" "enable" ] then
      config.services.router-tailscale.enable
    else
      false;
  tailscalePort =
    if hasRouterOption [ "services" "router-tailscale" "port" ] then
      config.services.router-tailscale.port
    else
      null;
in
{
  options.services.router-netbird = {
    enable = mkEnableOption "router-aware Netbird defaults";

    clientName = mkOption {
      type = types.str;
      default = "router";
      description = ''
        Name of the services.netbird.clients entry to create.
        The Netbird daemon systemd service will be named netbird-router.service.
      '';
    };

    interfaceName = mkOption {
      type = types.str;
      default = "nb-router";
      description = "Netbird interface name exposed to router-firewall.";
    };

    port = mkOption {
      type = types.port;
      default = 51821;
      description = ''
        UDP port used by the Netbird daemon.
        Defaults to 51821 (not 51820) so that Tailscale and Netbird can be
        enabled simultaneously without a port conflict.
      '';
    };

    setupKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/agenix/netbird-setup-key";
      description = ''
        Path to a file containing a Netbird setup key.
        When set, enables automated login on first boot.
        The file must be readable by the Netbird daemon user.
      '';
    };

    setupKeyDependencies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "agenix.service" ];
      description = ''
        Extra systemd units that must succeed before the setup key file
        is available (e.g., a secrets manager that decrypts it at boot).
      '';
    };

    useRoutingFeatures = mkOption {
      type = types.enum [
        "none"
        "client"
        "server"
        "both"
      ];
      default = "server";
      description = ''
        Controls kernel-level routing support for Netbird subnet routes and
        exit-node features. Defaults to "server" for router deployments, which
        enables IP forwarding. Set to "both" if this router also consumes routes
        advertised by other Netbird peers.
      '';
    };

    trustedInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Register the Netbird interface as an overlay interface in router-firewall.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the Netbird UDP port on WAN when router-firewall is enabled.";
    };

    logLevel = mkOption {
      type = types.enum [
        "panic"
        "fatal"
        "error"
        "warn"
        "info"
        "debug"
        "trace"
      ];
      default = "info";
      description = "Netbird daemon log level.";
    };

    hardened = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run the Netbird daemon as a dedicated user with minimal permissions.
        Disable only if another layer requires running netbird as root.
      '';
    };

    dnsResolverAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "127.0.0.2";
      description = ''
        Bind Netbird's internal DNS resolver to this address instead of the
        dynamic Netbird interface address. Useful when your LAN DNS server
        (Technitium, Unbound) needs a stable loopback address to forward the
        Netbird domain to, especially when running alongside Tailscale MagicDNS.
      '';
    };

    dnsResolverPort = mkOption {
      type = types.port;
      default = 53;
      description = "Port for the Netbird DNS resolver when dnsResolverAddress is set.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(tailscaleEnabled && tailscalePort != null && cfg.port == tailscalePort);
        message = ''
          services.router-netbird and services.router-tailscale are both enabled
          and share the same UDP port (${toString cfg.port}).
          Set services.router-netbird.port to a distinct value (default: 51821).
        '';
      }
    ];

    services = {
      netbird = {
        useRoutingFeatures = mkDefault cfg.useRoutingFeatures;

        clients.${cfg.clientName} = {
          port = mkDefault cfg.port;
          interface = mkDefault cfg.interfaceName;
          logLevel = mkDefault cfg.logLevel;
          hardened = mkDefault cfg.hardened;
          openFirewall = mkDefault (!firewallEnabled && cfg.openFirewall);

          dns-resolver = mkIf (cfg.dnsResolverAddress != null) {
            address = cfg.dnsResolverAddress;
            port = cfg.dnsResolverPort;
          };

          login = mkIf (cfg.setupKeyFile != null) {
            enable = true;
            setupKeyFile = cfg.setupKeyFile;
            systemdDependencies = cfg.setupKeyDependencies;
          };
        };
      };
    } // optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      router-firewall = mkIf firewallEnabled {
        overlayInterfaces = mkIf cfg.trustedInterface [ cfg.interfaceName ];
        wanUdpPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };
  };
}
