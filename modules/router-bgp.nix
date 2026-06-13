{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-bgp;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    hasRouterOption [ "services" "router-firewall" "enable" ]
    && (config.services.router-firewall.enable or false);
  routerHaEnabled =
    hasRouterOption [ "services" "router-ha" "enable" ]
    && (config.services.router-ha.enable or false);

  neighborIps = attrNames cfg.neighbors;

  sanitize = value: replaceStrings [ "." ":" "/" "-" ] [ "_" "_" "_" "_" ] value;

  afiHeading =
    afi:
    if afi == "ipv4-unicast" then
      "ipv4 unicast"
    else
      "ipv6 unicast";

  prefixListCommand =
    afi:
    if afi == "ipv4-unicast" then
      "ip prefix-list"
    else
      "ipv6 prefix-list";

  policySubmodule =
    types.submodule {
      options = {
        allowCidrs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Prefixes explicitly permitted by this policy.";
        };

        denyCidrs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Prefixes explicitly denied by this policy.";
        };

        defaultAction = mkOption {
          type = types.enum [
            "permit"
            "deny"
          ];
          default = "deny";
          description = "Default action after the explicit allow/deny lists.";
        };
      };
    };

  policyFamilySubmodule =
    types.submodule {
      options = {
        ipv4Unicast = mkOption {
          type = types.nullOr policySubmodule;
          default = null;
          description = "Bounded policy for IPv4 unicast.";
        };

        ipv6Unicast = mkOption {
          type = types.nullOr policySubmodule;
          default = null;
          description = "Bounded policy for IPv6 unicast.";
        };
      };
    };

  enabledAddressFamilies =
    filter
      (
        afi:
        if afi == "ipv4-unicast" then
          cfg.addressFamilies.ipv4Unicast.enable || cfg.networks != [ ]
        else
          cfg.addressFamilies.ipv6Unicast.enable
      )
      [
        "ipv4-unicast"
        "ipv6-unicast"
      ];

  ipv4Networks =
    if cfg.addressFamilies.ipv4Unicast.networks != [ ] then
      cfg.addressFamilies.ipv4Unicast.networks
    else
      cfg.networks;

  ipv6Networks = cfg.addressFamilies.ipv6Unicast.networks;

  mkPolicyBlocks =
    neighborIp: direction: afi: policy:
    let
      neighborToken = sanitize neighborIp;
      afiToken = sanitize afi;
      routeMapName = "RBGP_${neighborToken}_${afiToken}_${direction}";
      allowListName = "${routeMapName}_ALLOW";
      denyListName = "${routeMapName}_DENY";
      prefixCmd = prefixListCommand afi;
      mkPrefixLines =
        listName: action: cidrs:
        concatStringsSep "\n" (
          imap0 (idx: cidr: "${prefixCmd} ${listName} seq ${toString ((idx + 1) * 10)} ${action} ${cidr}") cidrs
        );
      matchKeyword =
        if afi == "ipv4-unicast" then
          "match ip address prefix-list"
        else
          "match ipv6 address prefix-list";
    in
    ''
      ${optionalString (policy.denyCidrs != [ ]) (mkPrefixLines denyListName "permit" policy.denyCidrs)}
      ${optionalString (policy.allowCidrs != [ ]) (mkPrefixLines allowListName "permit" policy.allowCidrs)}
      route-map ${routeMapName} deny 10
       ${optionalString (policy.denyCidrs != [ ]) "${matchKeyword} ${denyListName}"}
      ${optionalString (policy.allowCidrs != [ ]) ''
        route-map ${routeMapName} permit 20
         ${matchKeyword} ${allowListName}
      ''}
      route-map ${routeMapName} ${policy.defaultAction} 100
    '';

  mkNeighborPolicyReference =
    neighborIp: direction: afi: policy:
    let
      routeMapName = "RBGP_${sanitize neighborIp}_${sanitize afi}_${direction}";
    in
    optionalString (policy != null) "neighbor ${neighborIp} route-map ${routeMapName} ${direction}";

  neighborSecrets =
    concatMap
      (
        entry:
        let
          ip = entry.name;
          neighbor = entry.value;
        in
        optional (neighbor.passwordFile != null) {
          inherit ip;
          passwordFile = neighbor.passwordFile;
          placeholder = "__ROUTER_BGP_SECRET_${sanitize ip}__";
        }
      )
      (attrsToList cfg.neighbors);

  staticConfig = ''
    router bgp ${toString cfg.asn}
      ${optionalString (cfg.routerId != null) "bgp router-id ${cfg.routerId}"}
      ${concatStringsSep "\n" (mapAttrsToList (ip: neighbor: ''
        neighbor ${ip} remote-as ${toString neighbor.remoteAs}
        ${optionalString (neighbor.description != "") "neighbor ${ip} description ${neighbor.description}"}
        ${optionalString (neighbor.passwordFile != null) "neighbor ${ip} password __ROUTER_BGP_SECRET_${sanitize ip}__"}
        ${optionalString cfg.ha.singleActiveOwner "neighbor ${ip} shutdown"}
      '') cfg.neighbors)}
      ${concatStringsSep "\n" (
        concatMap
          (
            entry:
            let
              ip = entry.name;
              neighbor = entry.value;
            in
            concatMap
              (
                afi:
                let
                  importPolicy =
                    if afi == "ipv4-unicast" then
                      neighbor.importPolicy.ipv4Unicast
                    else
                      neighbor.importPolicy.ipv6Unicast;
                  exportPolicy =
                    if afi == "ipv4-unicast" then
                      neighbor.exportPolicy.ipv4Unicast
                    else
                      neighbor.exportPolicy.ipv6Unicast;
                in
                optionals (builtins.elem afi neighbor.addressFamilies) (
                  optional (importPolicy != null) (mkPolicyBlocks ip "in" afi importPolicy)
                  ++ optional (exportPolicy != null) (mkPolicyBlocks ip "out" afi exportPolicy)
                )
              )
              enabledAddressFamilies
          )
          (attrsToList cfg.neighbors)
      )}
      ${concatStringsSep "\n" (map (afi: ''
        address-family ${afiHeading afi}
          ${concatStringsSep "\n" (
            concatMap
              (
                entry:
                let
                  ip = entry.name;
                  neighbor = entry.value;
                  importPolicy =
                    if afi == "ipv4-unicast" then
                      neighbor.importPolicy.ipv4Unicast
                    else
                      neighbor.importPolicy.ipv6Unicast;
                  exportPolicy =
                    if afi == "ipv4-unicast" then
                      neighbor.exportPolicy.ipv4Unicast
                    else
                      neighbor.exportPolicy.ipv6Unicast;
                in
                optionals (builtins.elem afi neighbor.addressFamilies) [
                  "neighbor ${ip} activate"
                  (optionalString neighbor.nextHopSelf "neighbor ${ip} next-hop-self")
                  (mkNeighborPolicyReference ip "in" afi importPolicy)
                  (mkNeighborPolicyReference ip "out" afi exportPolicy)
                ]
              )
              (attrsToList cfg.neighbors)
          )}
          ${concatStringsSep "\n" (
            map
              (network: "network ${network}")
              (
                if afi == "ipv4-unicast" then
                  ipv4Networks
                else
                  ipv6Networks
              )
          )}
        exit-address-family
      '') enabledAddressFamilies)}
    !
  '';

  preStartSecretMaterialization =
    optionalString (neighborSecrets != [ ]) ''
      cp /etc/frr/frr.conf /run/frr/frr.conf
      chmod 0640 /run/frr/frr.conf
      chown frr:frr /run/frr/frr.conf
      ${concatStringsSep "\n" (map (secret: ''
        secret_tmp="$(${pkgs.coreutils}/bin/mktemp /run/frr/router-bgp-secret.XXXXXX)"
        chmod 0600 "$secret_tmp"
        chown frr:frr "$secret_tmp"
        ${pkgs.coreutils}/bin/tr -d '\n' < ${escapeShellArg secret.passwordFile} > "$secret_tmp"
        ${pkgs.python3Minimal}/bin/python - ${escapeShellArg secret.placeholder} /run/frr/frr.conf "$secret_tmp" <<'PY'
import pathlib
import sys

placeholder, path, secret_path = sys.argv[1:]
target = pathlib.Path(path)
value = pathlib.Path(secret_path).read_text()
target.write_text(target.read_text().replace(placeholder, value))
PY
        rm -f "$secret_tmp"
      '') neighborSecrets)}
      rm -f /etc/frr/frr.conf
      ln -s /run/frr/frr.conf /etc/frr/frr.conf
    '';
in
{
  options.services.router-bgp = {
    enable = mkEnableOption "Simplified BGP routing via FRR";

    asn = mkOption {
      type = types.ints.unsigned;
      example = 65001;
      description = "Local Autonomous System Number (ASN).";
    };

    routerId = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "10.10.10.1";
      description = ''
        BGP Router ID.

        In HA-capable or IPv6-native deployments, prefer a stable unique per-node
        IPv4-style identifier rather than a shared VIP or a dynamic LAN address.
      '';
    };

    neighbors = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          remoteAs = mkOption {
            type = types.ints.unsigned;
            description = "Remote ASN.";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Description for the neighbor.";
          };
          nextHopSelf = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to set next-hop-self for this neighbor.";
          };
          passwordFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "/run/agenix/bgp-upstream-password";
            description = "Runtime file containing the neighbor password.";
          };
          addressFamilies = mkOption {
            type = types.listOf (types.enum [ "ipv4-unicast" "ipv6-unicast" ]);
            default = [ "ipv4-unicast" ];
            description = "Address families activated for this neighbor.";
          };
          importPolicy = mkOption {
            type = policyFamilySubmodule;
            default = { };
            description = "Bounded per-neighbor import policy by address family.";
          };
          exportPolicy = mkOption {
            type = policyFamilySubmodule;
            default = { };
            description = "Bounded per-neighbor export policy by address family.";
          };
        };
      });
      default = { };
      example = {
        "10.10.11.50" = {
          remoteAs = 65002;
          description = "Proxmox Node 1";
          passwordFile = "/run/agenix/proxmox-bgp-password";
          addressFamilies = [
            "ipv4-unicast"
            "ipv6-unicast"
          ];
        };
      };
      description = "BGP neighbors to peer with.";
    };

    networks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "10.10.0.0/16" ];
      description = "Legacy IPv4 network prefixes to advertise via BGP.";
    };

    addressFamilies = {
      ipv4Unicast = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable IPv4 unicast address-family rendering.";
        };

        networks = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "IPv4 prefixes to advertise inside address-family ipv4 unicast.";
        };
      };

      ipv6Unicast = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable IPv6 unicast address-family rendering.";
        };

        networks = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "IPv6 prefixes to advertise inside address-family ipv6 unicast.";
        };
      };
    };

    ha = {
      singleActiveOwner = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable promotion-aware BGP ownership for HA deployments.

          When true, all BGP neighbors start in shutdown state. The VRRP
          master promotion hook activates them via vtysh, and demotion
          shuts them down again. This ensures only the active HA node
          presents BGP peering identity.

          Requires services.router-ha.enable = true.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services = {
      frr = {
        bgpd.enable = true;
        config = staticConfig;
      };
    } // optionalAttrs (hasRouterOption [ "services" "router-firewall" "trustedTcpPorts" ]) {
      router-firewall = mkIf firewallEnabled {
        trustedTcpPorts = [ 179 ];
      };
    };

    assertions =
      [
        {
          assertion = !routerHaEnabled || cfg.ha.singleActiveOwner;
          message = ''
            services.router-bgp with services.router-ha requires explicit
            promotion-aware ownership. Set:
              services.router-bgp.ha.singleActiveOwner = true;
            This ensures BGP neighbors are shutdown on backup nodes and only
            activated on VRRP master promotion.
          '';
        }
        {
          assertion = cfg.ha.singleActiveOwner -> routerHaEnabled;
          message = ''
            services.router-bgp.ha.singleActiveOwner requires
            services.router-ha.enable = true.
          '';
        }
      ]
      ++ concatMap
        (
          entry:
          let
            ip = entry.name;
            neighbor = entry.value;
            checkPolicy =
              afi: policy:
              optional (policy != null) {
                assertion = builtins.elem afi neighbor.addressFamilies && builtins.elem afi enabledAddressFamilies;
                message = "router-bgp neighbor ${ip} defines ${afi} policy without activating that address family.";
              };
          in
          (map
            (afi: {
              assertion = builtins.elem afi enabledAddressFamilies;
              message = "router-bgp neighbor ${ip} activates ${afi} but that address family is not enabled globally.";
            })
            neighbor.addressFamilies)
          ++ checkPolicy "ipv4-unicast" neighbor.importPolicy.ipv4Unicast
          ++ checkPolicy "ipv6-unicast" neighbor.importPolicy.ipv6Unicast
          ++ checkPolicy "ipv4-unicast" neighbor.exportPolicy.ipv4Unicast
          ++ checkPolicy "ipv6-unicast" neighbor.exportPolicy.ipv6Unicast
        )
        (attrsToList cfg.neighbors);

    networking.firewall.allowedTCPPorts = mkIf (!firewallEnabled) [ 179 ];

    systemd.services.frr = mkIf (neighborSecrets != [ ]) {
      preStart = preStartSecretMaterialization;
      restartTriggers = map (secret: secret.passwordFile) neighborSecrets;
    };
  };
}
