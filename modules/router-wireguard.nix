{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-wireguard;
  hasRouterOption = path: hasAttrByPath path options;
  optimizationInterfaces = config.services.router-optimizations.interfaces or { };
  firewallWanInterfaces =
    if hasRouterOption [ "services" "router-firewall" "wanInterfaces" ] then
      config.services.router-firewall.wanInterfaces or [ ]
    else
      [ ];
  wanInterfaces =
    if firewallWanInterfaces != [ ] then
      firewallWanInterfaces
    else
      mapAttrsToList (_name: iface: iface.device) (
        filterAttrs (_name: iface: iface.role == "wan") optimizationInterfaces
      );
  routeToWanRule = optionalString (cfg.routeToWan && wanInterfaces != [ ]) ''
    iifname "${cfg.interfaceName}" oifname { ${concatStringsSep ", " (map (iface: "\"${iface}\"") wanInterfaces)} } accept
  '';
in
{
  options.services.router-wireguard = {
    enable = mkEnableOption "router-aware WireGuard defaults";

    interfaceName = mkOption {
      type = types.str;
      default = "wg0";
      description = "WireGuard interface name.";
    };

    ips = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.20.0.1/24" "fd42::1/64" ];
      description = "IP addresses assigned to the WireGuard interface.";
    };

    listenPort = mkOption {
      type = types.nullOr types.port;
      default = 51820;
      description = "UDP port exposed for incoming WireGuard peers.";
    };

    privateKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to the WireGuard private key file.";
    };

    generatePrivateKeyFile = mkOption {
      type = types.bool;
      default = false;
      description = "Generate a private key file automatically when no key is provisioned yet.";
    };

    mtu = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Optional MTU override for the WireGuard interface.";
    };

    trustedInterface = mkOption {
      type = types.bool;
      default = false;
      description = "Treat the WireGuard tunnel as a trusted router interface.";
    };

    routeToWan = mkOption {
      type = types.bool;
      default = false;
      description = "Allow WireGuard clients to forward traffic to WAN through router-firewall.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the WireGuard UDP listen port on WAN through router-firewall.";
    };

    allowedIPsAsRoutes = mkOption {
      type = types.bool;
      default = true;
      description = "Install peer allowed IPs as routes automatically.";
    };

    peers = mkOption {
      type = types.listOf (types.submodule {
        options = {
          publicKey = mkOption {
            type = types.singleLineStr;
            description = "Base64 public key of the WireGuard peer.";
          };

          allowedIPs = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Allowed IPs routed to or accepted from this peer.";
          };

          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional endpoint in host:port form.";
          };

          presharedKeyFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional preshared key file.";
          };

          persistentKeepalive = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Optional keepalive interval in seconds.";
          };
        };
      });
      default = [ ];
      description = "WireGuard peers attached to the router interface.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.privateKeyFile != null || cfg.generatePrivateKeyFile;
        message = "router-wireguard requires privateKeyFile or generatePrivateKeyFile.";
      }
    ];

    networking.wireguard.interfaces.${cfg.interfaceName} = {
      ips = cfg.ips;
      listenPort = cfg.listenPort;
      privateKeyFile = cfg.privateKeyFile;
      generatePrivateKeyFile = cfg.generatePrivateKeyFile;
      allowedIPsAsRoutes = cfg.allowedIPsAsRoutes;
      mtu = cfg.mtu;
      peers = map (peer: {
        inherit (peer) publicKey allowedIPs endpoint presharedKeyFile persistentKeepalive;
      }) cfg.peers;
    };

    services.router-firewall = mkIf (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      extraTrustedInterfaces = mkIf cfg.trustedInterface [ cfg.interfaceName ];
      wanUdpPorts = mkIf (cfg.openFirewall && cfg.listenPort != null) [ cfg.listenPort ];
      extraForwardRules = mkIf (cfg.routeToWan && wanInterfaces != [ ]) routeToWanRule;
    };
  };
}
