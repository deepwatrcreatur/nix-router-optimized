{
  config,
  lib,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-openvpn;
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
  mkWanRule = iface: optionalString (iface.routeToWan && wanInterfaces != [ ]) ''
    iifname "${iface.interfaceName}" oifname { ${concatStringsSep ", " (map (dev: "\"${dev}\"") wanInterfaces)} } accept
  '';
  trustedInterfaces = mapAttrsToList (_name: instance: instance.interfaceName) (
    filterAttrs (_name: instance: instance.trustedInterface) cfg.instances
  );
  wanUdpPorts = unique (concatLists (mapAttrsToList (_name: instance: instance.wanUdpPorts) cfg.instances));
  wanTcpPorts = unique (concatLists (mapAttrsToList (_name: instance: instance.wanTcpPorts) cfg.instances));
  extraForwardRules = concatStringsSep "\n" (filter (rule: rule != "") (mapAttrsToList (_name: instance: mkWanRule instance) cfg.instances));
in
{
  options.services.router-openvpn = {
    instances = mkOption {
      default = { };
      description = "Router-shaped OpenVPN instances mapped to services.openvpn.servers.";
      type = types.attrsOf (types.submodule {
        options = {
          interfaceName = mkOption {
            type = types.str;
            default = "tun0";
            description = "Tunnel interface name used for firewall integration. Keep it aligned with the OpenVPN config.";
          };

          config = mkOption {
            type = types.lines;
            description = "Raw OpenVPN configuration passed to services.openvpn.servers.<name>.config.";
          };

          up = mkOption {
            type = types.lines;
            default = "";
            description = "Shell commands run after the instance comes up.";
          };

          down = mkOption {
            type = types.lines;
            default = "";
            description = "Shell commands run during shutdown.";
          };

          autoStart = mkOption {
            type = types.bool;
            default = true;
            description = "Start this OpenVPN instance automatically.";
          };

          updateResolvConf = mkOption {
            type = types.bool;
            default = false;
            description = "Use update-resolv-conf for this instance.";
          };

          authUserPass = mkOption {
            type = types.nullOr (types.oneOf [
              types.singleLineStr
              (types.submodule {
                options = {
                  username = mkOption {
                    type = types.str;
                  };
                  password = mkOption {
                    type = types.str;
                  };
                };
              })
            ]);
            default = null;
            description = "Optional auth-user-pass credentials, forwarded to services.openvpn.";
          };

          trustedInterface = mkOption {
            type = types.bool;
            default = false;
            description = "Treat this OpenVPN tunnel as a trusted router interface.";
          };

          routeToWan = mkOption {
            type = types.bool;
            default = false;
            description = "Allow traffic arriving from this OpenVPN interface to forward to WAN.";
          };

          wanUdpPorts = mkOption {
            type = types.listOf types.port;
            default = [ ];
            description = "WAN UDP ports opened for this OpenVPN instance.";
          };

          wanTcpPorts = mkOption {
            type = types.listOf types.port;
            default = [ ];
            description = "WAN TCP ports opened for this OpenVPN instance.";
          };
        };
      });
    };
  };

  config = mkIf (cfg.instances != { }) {
    services.openvpn.servers = mapAttrs (_name: instance: {
      inherit (instance) config up down autoStart updateResolvConf authUserPass;
    }) cfg.instances;

    services.router-firewall = mkIf (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      extraTrustedInterfaces = trustedInterfaces;
      wanUdpPorts = wanUdpPorts;
      wanTcpPorts = wanTcpPorts;
      extraForwardRules = mkIf (extraForwardRules != "") extraForwardRules;
    };
  };
}
