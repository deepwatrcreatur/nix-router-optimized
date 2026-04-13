{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-zerotier;
  hasRouterOption = path: hasAttrByPath path options;

  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;

  netbirdEnabled =
    if hasRouterOption [ "services" "router-netbird" "enable" ] then
      config.services.router-netbird.enable
    else
      false;
  netbirdPort =
    if hasRouterOption [ "services" "router-netbird" "port" ] then
      config.services.router-netbird.port
    else
      null;

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

  needsForwarding = elem cfg.useRoutingFeatures [
    "server"
    "both"
  ];
in
{
  options.services.router-zerotier = {
    enable = mkEnableOption "router-aware ZeroTier defaults";

    interfaceName = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "zt3jnkd4l9";
      description = ''
        ZeroTier interface name exposed to router-firewall.

        ZeroTier derives interface names from the joined network and names them
        ztXXXXXXXX at runtime. Set this explicitly when trustedInterface is
        enabled because router-firewall requires exact interface names.
      '';
    };

    joinNetworks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "a8a2c3c10c1a68de" ];
      description = "ZeroTier network IDs to join on startup.";
    };

    port = mkOption {
      type = types.port;
      default = 9993;
      description = "UDP port used by ZeroTier.";
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
        Controls kernel-level routing support for ZeroTier subnet routing.
        ZeroTier does not expose a native NixOS useRoutingFeatures option, so
        "server" and "both" enable IPv4 and IPv6 forwarding with sysctl.
      '';
    };

    trustedInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Register the ZeroTier interface as an overlay interface in router-firewall.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the ZeroTier UDP port on WAN when router-firewall is enabled.";
    };

    secretFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/agenix/zerotier-identity-secret";
      description = ''
        Optional path to a ZeroTier identity.secret file for a persistent node
        ID. When set, the file is copied to /var/lib/zerotier-one/identity.secret
        before the daemon starts.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.trustedInterface || cfg.interfaceName != null;
        message = ''
          services.router-zerotier.trustedInterface is enabled, but
          services.router-zerotier.interfaceName is not set. ZeroTier interface
          names are dynamic (ztXXXXXXXX), so set the exact runtime interface name
          or disable trustedInterface.
        '';
      }
      {
        assertion = !(netbirdEnabled && netbirdPort != null && cfg.port == netbirdPort);
        message = ''
          services.router-zerotier and services.router-netbird are both enabled
          and share the same UDP port (${toString cfg.port}). Set one overlay
          module to a distinct port.
        '';
      }
      {
        assertion = !(tailscaleEnabled && tailscalePort != null && cfg.port == tailscalePort);
        message = ''
          services.router-zerotier and services.router-tailscale are both enabled
          and share the same UDP port (${toString cfg.port}). Set one overlay
          module to a distinct port.
        '';
      }
    ];

    services = {
      zerotierone = {
        enable = mkDefault true;
        joinNetworks = mkDefault cfg.joinNetworks;
        port = mkDefault cfg.port;
      };
    } // optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      router-firewall = mkIf firewallEnabled {
        overlayInterfaces = mkIf cfg.trustedInterface (optional (cfg.interfaceName != null) cfg.interfaceName);
        wanUdpPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };

    boot.kernel.sysctl = mkIf needsForwarding {
      "net.ipv4.ip_forward" = mkDefault 1;
      "net.ipv6.conf.all.forwarding" = mkDefault 1;
    };

    systemd.services.zerotierone.preStart = mkIf (cfg.secretFile != null) (mkBefore ''
      install -D -m 0600 -o root -g root ${cfg.secretFile} /var/lib/zerotier-one/identity.secret
    '');
  };
}
