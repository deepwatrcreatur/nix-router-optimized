{
  config,
  options,
  lib,
  pkgs,
  ...
}:

# Route-based IPsec: strongSwan (swanctl) negotiates SAs bound by if_id to
# an XFRM interface, so routing, not policy, decides what is encrypted.
# See docs/router-ipsec.md.
with lib;

let
  cfg = config.services.router-ipsec;
  ipLib = import ./lib/ip.nix { inherit lib; };
  hasRouterFirewall = hasAttrByPath [ "services" "router-firewall" "enable" ] options;
  firewallEnabled = hasRouterFirewall && (config.services.router-firewall.enable or false);
  hasRouterZones = hasAttrByPath [ "services" "router-zones" "zones" ] options;
  hasRouterBgp = hasAttrByPath [ "services" "router-bgp" "neighbors" ] options;
  bgpNeighbors = if hasRouterBgp && (config.services.router-bgp.enable or false) then attrNames config.services.router-bgp.neighbors else [ ];

  # INVARIANT: mirrors router-firewall's wanInterfaces fallback (explicit list,
  # else router-optimizations interfaces with role "wan").
  firewallWanInterfaces =
    let
      fw = config.services.router-firewall;
      byRole = mapAttrsToList (_: i: i.device) (
        filterAttrs (_: i: i.role == "wan") (config.services.router-optimizations.interfaces or { })
      );
    in
    if firewallEnabled then (if fw.wanInterfaces != [ ] then fw.wanInterfaces else byRole) else [ ];

  isIpv4Literal = s: builtins.match "([0-9]{1,3}\\.){3}[0-9]{1,3}" s != null;
  secretsFile = "/run/router-ipsec/secrets.conf";
  # Above any routing daemon's metric (FRR installs BGP routes with 20).
  blackholeMetric = 4000;
  quote = d: ''"${d}"'';

  # INVARIANT: zones this module did not define itself; its own interface
  # contribution would otherwise make any zone name "exist".
  definedZones =
    if hasRouterZones then
      concatMap (d: attrNames d.value) (
        filter (d: baseNameOf d.file != "router-ipsec.nix") options.services.router-zones.zones.definitionsWithLocations
      )
    else
      [ ];

  tunnelBgpNeighbors = t: filter (ip: isIpv4Literal ip && ipLib.cidrContainsIP t.address ip) bgpNeighbors;

  tunnelModule =
    { name, config, ... }:
    {
      options = {
        interface = mkOption {
          type = types.str;
          default = "xfrm-${name}";
          defaultText = literalExpression ''"xfrm-<name>"'';
          description = "Name of the XFRM interface (at most 15 characters).";
        };

        ifId = mkOption {
          type = types.ints.between 1 4294967295;
          example = 10;
          description = "XFRM interface ID binding the SAs to the interface (unique per tunnel).";
        };

        address = mkOption {
          type = types.str;
          example = "169.254.10.1/30";
          description = "IPv4 address and prefix inside the tunnel (used for BGP or as a next hop).";
        };

        routes = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "10.20.0.0/16" ];
          description = "Static routes sent through the tunnel. Not needed for prefixes learned by BGP.";
        };

        remotePrefixes = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "10.20.0.0/16" ];
          description = ''
            Prefixes that must only ever be reached through this tunnel, such
            as those learned by BGP. Each gets a blackhole route with metric
            ${toString blackholeMetric}, so if BGP withdraws the prefix (or the
            tunnel is down) traffic is dropped instead of leaving in the clear
            via the WAN default route. `routes` need none: they always point
            at the XFRM interface, which drops without an SA.
          '';
        };

        remote = {
          address = mkOption {
            type = types.str;
            example = "203.0.113.20";
            description = "Peer's public address or hostname. `%any` accepts a peer from any address (responder only).";
          };
          id = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Peer IKE identity; defaults to `remote.address`.";
          };
        };

        local = {
          address = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Local address IKE uses; `null` lets the kernel pick (the WAN address).";
          };
          id = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Local IKE identity; defaults to `local.address` or the local IP.";
          };
        };

        pskFile = mkOption {
          type = types.str;
          example = "/run/agenix/ipsec-branch-psk";
          description = ''
            Runtime file holding the pre-shared key. It is read when strongSwan
            starts and never copied into the Nix store.
          '';
        };

        initiate = mkOption {
          type = types.bool;
          default = true;
          description = "Bring the tunnel up at start, retry on traffic if the peer was not ready, and re-establish after it closes. Set false on a responder-only side.";
        };

        proposals = {
          ike = mkOption {
            type = types.listOf types.str;
            default = [ "aes256gcm16-prfsha384-ecp384" "aes256-sha256-modp3072" ];
            description = "IKE proposals, in strongSwan syntax.";
          };
          esp = mkOption {
            type = types.listOf types.str;
            default = [ "aes256gcm16-ecp384" "aes256-sha256-modp3072" ];
            description = "ESP proposals, in strongSwan syntax (with PFS group).";
          };
        };

        zone = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "vpn";
          description = "router-zones zone the tunnel interface joins. The zone must exist.";
        };

        allowInputTcpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = ''
            Router services reachable through the tunnel. TCP 179 is added
            automatically when a router-bgp neighbor sits inside `address`.
          '';
        };
      };
    };

  tunnels = cfg.tunnels;

  # INVARIANT: secrets are hex-encoded so any PSK byte survives swanctl's
  # quoting; the file is root-only under /run.
  writeSecrets = pkgs.writeShellScript "router-ipsec-secrets" ''
    set -euo pipefail
    umask 077
    ${pkgs.coreutils}/bin/install -d -m 0700 /run/router-ipsec
    tmp=$(${pkgs.coreutils}/bin/mktemp /run/router-ipsec/secrets.XXXXXX)
    {
      echo "secrets {"
      ${concatStringsSep "\n" (
        mapAttrsToList (name: t: ''
          # Hex of the exact bytes, minus one trailing newline (from editors or
          # `echo`); newlines inside a binary key are kept.
          psk=$(${pkgs.xxd}/bin/xxd -p < ${escapeShellArg t.pskFile} | ${pkgs.coreutils}/bin/tr -d '\n')
          psk=''${psk%0a}
          test -n "$psk"
          echo "  ike-${name} {"
          ${optionalString (t.local.id != null) "echo '    id-local = ${t.local.id}'"}
          echo '    id-remote = ${if t.remote.id != null then t.remote.id else t.remote.address}'
          echo "    secret = 0x$psk"
          echo "  }"
        '') tunnels
      )}
      echo "}"
    } > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" ${secretsFile}
  '';
in
{
  # Names this module's definitions (see definedZones).
  _file = "router-ipsec.nix";

  options.services.router-ipsec = {
    enable = mkEnableOption "route-based IPsec tunnels (strongSwan swanctl with XFRM interfaces)";

    tunnels = mkOption {
      type = types.attrsOf (types.submodule tunnelModule);
      default = { };
      description = "IPsec tunnels keyed by name.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions =
        [
          {
            assertion = tunnels != { };
            message = "services.router-ipsec.enable needs at least one tunnel.";
          }
          {
            assertion = allUnique (mapAttrsToList (_: t: t.ifId) tunnels);
            message = "services.router-ipsec.tunnels: ifId values must be unique.";
          }
          {
            assertion = allUnique (mapAttrsToList (_: t: t.interface) tunnels);
            message = "services.router-ipsec.tunnels: interface names must be unique.";
          }
          {
            # SECURITY: with no WAN interfaces the IKE/ESP rules would match
            # every interface, including LANs.
            assertion = !firewallEnabled || firewallWanInterfaces != [ ];
            message = "services.router-ipsec needs WAN interfaces in router-firewall (wanInterfaces or a router-optimizations interface with role \"wan\") to scope IKE and ESP.";
          }
          {
            # GOTCHA: flowtable offload with XFRM interfaces is not verified
            # here; keep tunnels out of it (docs/router-ipsec.md#flowtables).
            assertion =
              !(firewallEnabled && (config.services.router-firewall.flowtable.enable or false))
              || all (t: !(elem t.interface config.services.router-firewall.flowtable.interfaces)) (attrValues tunnels);
            message = "services.router-ipsec: tunnel interfaces must not be in services.router-firewall.flowtable.interfaces.";
          }
        ]
        ++ concatLists (
          mapAttrsToList (name: t: [
            {
              assertion = stringLength t.interface <= 15;
              message = "services.router-ipsec.tunnels.${name}.interface \"${t.interface}\" is longer than 15 characters.";
            }
            {
              assertion = builtins.match "([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}" t.address != null;
              message = "services.router-ipsec.tunnels.${name}.address must be an IPv4 CIDR such as 169.254.10.1/30.";
            }
            {
              # WHY: a route covering the peer's public address sends IKE and
              # ESP into the tunnel itself, which then never comes up.
              assertion =
                !isIpv4Literal t.remote.address
                || all (r: !(ipLib.cidrContainsIP r t.remote.address)) (filter (r: !hasInfix ":" r) (t.routes ++ t.remotePrefixes));
              message = "services.router-ipsec.tunnels.${name}: routes or remotePrefixes cover the peer address ${t.remote.address}; IKE would be routed into the tunnel.";
            }
            {
              assertion = !hasPrefix "/nix/store" t.pskFile;
              message = "services.router-ipsec.tunnels.${name}.pskFile must be a runtime path, not a store path.";
            }
            {
              assertion = t.remote.address != "%any" || !t.initiate;
              message = "services.router-ipsec.tunnels.${name}: a peer at %any cannot be initiated to; set initiate = false.";
            }
            {
              assertion = t.zone == null || elem t.zone definedZones;
              message = "services.router-ipsec.tunnels.${name}.zone \"${toString t.zone}\" is not a services.router-zones zone.";
            }
          ]) tunnels
        );

      warnings = mapAttrsToList (
        name: t:
        "services.router-ipsec.tunnels.${name}: remote.address \"${t.remote.address}\" is not an IPv4 literal, so the firewall accepts IKE/ESP on the WAN from any source for it."
      ) (filterAttrs (_: t: firewallEnabled && !isIpv4Literal t.remote.address) tunnels);

      # The XFRM interfaces, addresses and routes are networkd units.
      systemd.network.enable = mkDefault true;

      systemd.network.netdevs = mapAttrs' (
        name: t:
        nameValuePair "40-${t.interface}" {
          netdevConfig = {
            Kind = "xfrm";
            Name = t.interface;
          };
          # Independent: not tied to an underlying link, so it survives the
          # WAN going down on a VRRP backup.
          xfrmConfig = {
            InterfaceId = t.ifId;
            Independent = true;
          };
        }
      ) tunnels;

      systemd.network.networks = mapAttrs' (
        name: t:
        nameValuePair "40-${t.interface}" {
          matchConfig.Name = t.interface;
          address = [ t.address ];
          routes =
            map (d: { Destination = d; }) t.routes
            # SECURITY: blackholes keep remote prefixes off the WAN when BGP
            # withdraws them; BGP routes (metric 20) win while present.
            ++ map (d: {
              Destination = d;
              Type = "blackhole";
              Metric = blackholeMetric;
            }) t.remotePrefixes;
          linkConfig.RequiredForOnline = "no";
        }
      ) tunnels;

      services.strongswan-swanctl = {
        enable = true;
        includes = [ secretsFile ];
        swanctl.connections = mapAttrs (
          name: t:
          {
            version = 2;
            remote_addrs = [ t.remote.address ];
            proposals = t.proposals.ike;
            dpd_delay = "30s";
            local.main = {
              auth = "psk";
            }
            // optionalAttrs (t.local.id != null) { id = t.local.id; };
            remote.main = {
              auth = "psk";
              id = if t.remote.id != null then t.remote.id else t.remote.address;
            };
            children.${name} = {
              # Route-based: match everything; the routing table decides
              # what enters the XFRM interface.
              local_ts = [ "0.0.0.0/0" ];
              remote_ts = [ "0.0.0.0/0" ];
              if_id_in = toString t.ifId;
              if_id_out = toString t.ifId;
              esp_proposals = t.proposals.esp;
              # A responder must not start an exchange of its own.
              dpd_action = if t.initiate then "restart" else "clear";
              # WHY: "start" alone gives up for good if the peer is not ready
              # (NO_PROPOSAL_CHOSEN during its boot); the trap re-initiates on
              # the next packet routed into this if_id. A trap policy with an
              # if_id only matches traffic through that XFRM interface.
              start_action = if t.initiate then "trap|start" else "none";
              close_action = if t.initiate then "start" else "none";
            };
          }
          // optionalAttrs (t.local.address != null) { local_addrs = [ t.local.address ]; }
        ) tunnels;
      };

      systemd.services.router-ipsec-secrets = {
        description = "Render IPsec pre-shared keys for strongSwan";
        before = [ "strongswan-swanctl.service" ];
        requiredBy = [ "strongswan-swanctl.service" ];
        partOf = [ "strongswan-swanctl.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = writeSecrets;
        };
      };
    }

    (optionalAttrs hasRouterZones {
      services.router-zones.zones = mkMerge (
        mapAttrsToList (_: t: optionalAttrs (t.zone != null) { ${t.zone}.interfaces = [ t.interface ]; }) tunnels
      );
    })

    (optionalAttrs hasRouterFirewall {
      services.router-firewall.extraInputEarlyRules = mkIf firewallEnabled (
        let
          wanMatch = "iifname { ${concatMapStringsSep ", " quote firewallWanInterfaces} } ";
          peerRules =
            t:
            let
              src = optionalString (isIpv4Literal t.remote.address) "ip saddr ${t.remote.address} ";
            in
            ''
              ${wanMatch}${src}udp dport { 500, 4500 } accept comment "IPsec IKE"
              ${wanMatch}${src}meta l4proto esp accept comment "IPsec ESP"
            '';
          inputRules =
            t:
            let
              ports = unique (t.allowInputTcpPorts ++ optional (tunnelBgpNeighbors t != [ ]) 179);
            in
            optionalString (ports != [ ]) ''
              iifname ${quote t.interface} tcp dport { ${concatMapStringsSep ", " toString ports} } accept comment "IPsec tunnel services"
            '';
        in
        # SECURITY: IKE/ESP only on the WAN and, for literal peers, only from
        # the peer's address.
        concatStrings (mapAttrsToList (_: t: peerRules t + inputRules t) tunnels)
      );
    })
  ]);
}
