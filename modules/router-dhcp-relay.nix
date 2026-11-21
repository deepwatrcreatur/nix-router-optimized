{
  config,
  options,
  lib,
  ...
}:

# DHCPv4 relay (RFC 1542) for routed interfaces, using systemd-networkd's
# built-in relay mode ([DHCPServer] RelayTarget=). See docs/router-dhcp-relay.md.
with lib;

let
  cfg = config.services.router-dhcp-relay;
  routedIfaces = config.services.router-networking.routedInterfaces or { };
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  firewallEnabled = hasRouterFirewall && (config.services.router-firewall.enable or false);
  isIpv4 = s: builtins.match "([0-9]{1,3}\\.){3}[0-9]{1,3}" s != null;

  devices = mapAttrsToList (name: _: routedIfaces.${name}.device or name) cfg.interfaces;
  keaInterfaces = map (i: head (splitString "/" i)) (
    config.services.kea.dhcp4.settings.interfaces-config.interfaces or [ ]
  );
  keaEnabled = config.services.kea.dhcp4.enable or false;
  routerDhcpInterfaces = if (config.services.router-dhcp.enable or false) then attrNames (config.services.router-dhcp.interfaces or { }) else [ ];

  # networkd's option-82 suboption format is "string:<value>".
  suboption = v: "string:${v}";

  relayInterfaceModule =
    { name, ... }:
    {
      options = {
        server = mkOption {
          type = types.str;
          example = "10.10.10.1";
          description = ''
            IPv4 address of the DHCP server (or the next relay) to forward to.
            The server must route replies for this segment back to the
            relay's address on it (the giaddr).
          '';
        };

        circuitId = mkOption {
          type = types.nullOr types.str;
          default = routedIfaces.${name}.device or name;
          defaultText = literalExpression "services.router-networking.routedInterfaces.<name>.device";
          example = "office";
          description = ''
            Agent Circuit ID (option 82, suboption 1) added to relayed
            requests, so the server can tell segments apart. `null` omits it.
          '';
        };

        remoteId = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "branch-router";
          description = "Agent Remote ID (option 82, suboption 2). `null` omits it.";
        };
      };
    };
in
{
  options.services.router-dhcp-relay = {
    enable = mkEnableOption "DHCPv4 relay on routed interfaces via systemd-networkd";

    interfaces = mkOption {
      type = types.attrsOf (types.submodule relayInterfaceModule);
      default = { };
      example = literalExpression ''
        {
          office = {
            server = "10.10.10.1";
            remoteId = "branch-router";
          };
        }
      '';
      description = ''
        Routed interfaces (keyed by their `services.router-networking.routedInterfaces`
        name) whose DHCP requests are relayed instead of served locally.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions =
        [
          {
            assertion = cfg.interfaces != { };
            message = "services.router-dhcp-relay.enable needs at least one entry in services.router-dhcp-relay.interfaces.";
          }
        ]
        ++ concatLists (
          mapAttrsToList (name: relay: [
            {
              assertion = routedIfaces ? ${name};
              message = "services.router-dhcp-relay.interfaces.${name} requires a matching services.router-networking.routedInterfaces.${name}.";
            }
            {
              assertion = isIpv4 relay.server;
              message = "services.router-dhcp-relay.interfaces.${name}.server must be an IPv4 address (got \"${relay.server}\").";
            }
            {
              # WHY: a segment gets its leases from one place; a local server
              # and a relay on the same link would both answer.
              assertion = !(elem name routerDhcpInterfaces);
              message = "services.router-dhcp-relay.interfaces.${name}: services.router-dhcp.interfaces.${name} also serves this segment; remove one.";
            }
            {
              assertion = !(keaEnabled && elem (routedIfaces.${name}.device or name) keaInterfaces);
              message = "services.router-dhcp-relay.interfaces.${name}: Kea also serves ${routedIfaces.${name}.device or name}; remove it from services.router-kea.dhcp4.interfaces.";
            }
          ]) cfg.interfaces
        );

      systemd.network.networks = mapAttrs' (
        name: relay:
        nameValuePair "20-router-${name}" {
          networkConfig.DHCPServer = mkForce true;
          dhcpServerConfig =
            {
              RelayTarget = relay.server;
            }
            // optionalAttrs (relay.circuitId != null) { RelayAgentCircuitId = suboption relay.circuitId; }
            // optionalAttrs (relay.remoteId != null) { RelayAgentRemoteId = suboption relay.remoteId; };
        }
      ) cfg.interfaces;
    }

    (optionalAttrs hasRouterFirewall {
      # Client broadcasts arrive on the relayed segment; the server answers
      # the relay on UDP 67 from its own address.
      services.router-firewall.extraInputRules = mkIf firewallEnabled (
        concatStringsSep "\n" (
          [ "iifname { ${concatMapStringsSep ", " (d: ''"${d}"'') devices} } udp dport 67 accept comment \"DHCP relay clients\"" ]
          ++ map (s: "ip saddr ${s} udp sport 67 udp dport 67 accept comment \"DHCP relay server\"") (
            unique (mapAttrsToList (_: r: r.server) cfg.interfaces)
          )
        )
      );
    })
  ]);
}
