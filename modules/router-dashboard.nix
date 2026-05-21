# Router web dashboard with real-time traffic monitoring
# Enhanced version with Chart.js graphs and modular widgets
{
  config,
  lib,
  options,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.router-dashboard;
  technitiumRuntimeApiTokenPath = "/var/lib/private/technitium-dns-server/nix-router-api-token";
  hasRouterOption = path: hasAttrByPath path options;
  hasRouterNetworking = hasRouterOption [ "services" "router-networking" "routedInterfaces" ];
  hasRouterDhcp = hasRouterOption [ "services" "router-dhcp" "interfaces" ];
  hasRouterKea = hasRouterOption [ "services" "router-kea" "dhcp4" "subnet" ];
  hasRouterTechnitium = hasRouterOption [ "services" "router-technitium" "scopes" ];
  optimizationInterfaces =
    if hasRouterOption [ "services" "router-optimizations" "interfaces" ] then
      config.services.router-optimizations.interfaces or { }
    else
      { };
  routedInterfaces = if hasRouterNetworking then config.services.router-networking.routedInterfaces or { } else { };
  routerDhcpCfg = if hasRouterDhcp then config.services.router-dhcp else null;
  routerDhcpEffectiveInterfaces =
    if !hasRouterDhcp || !(routerDhcpCfg.enable or false) then
      { }
    else if routerDhcpCfg.interfaces != { } || !(routerDhcpCfg.autoInterfacesFromNetworking or true) then
      filterAttrs (_name: iface: iface.enable) (routerDhcpCfg.interfaces or { })
    else
      mapAttrs (_name: _iface: {
        enable = true;
        poolOffset = 100;
        poolSize = 100;
        defaultLeaseTimeSec = 3600;
        maxLeaseTimeSec = 43200;
        dns = null;
        emitDns = true;
        emitRouter = true;
        staticLeases = [ ];
        extraDhcpServerConfig = { };
      }) (
        filterAttrs (_name: iface: elem iface.role (routerDhcpCfg.matchRoles or [ ])) routedInterfaces
      );

  parseInt = s: builtins.fromJSON s;

  parseIPv4 =
    ip:
    let
      octets = splitString "." ip;
      parsedOctets = map parseInt octets;
      validOctets = all (o: o >= 0 && o <= 255) parsedOctets;
    in
    assert length octets == 4;
    assert validOctets;
    ((elemAt parsedOctets 0) * 16777216)
    + ((elemAt parsedOctets 1) * 65536)
    + ((elemAt parsedOctets 2) * 256)
    + (elemAt parsedOctets 3);

  mod = a: b: a - ((builtins.div a b) * b);

  intOctet = divisor: value: builtins.toString (mod (builtins.div value divisor) 256);

  renderIPv4 =
    value:
    concatStringsSep "." [
      (intOctet 16777216 value)
      (intOctet 65536 value)
      (intOctet 256 value)
      (builtins.toString (mod value 256))
    ];

  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);

  parseCidr =
    cidr:
    let
      parts = splitString "/" cidr;
      address = elemAt parts 0;
      prefixLength = parseInt (elemAt parts 1);
      hostCount = pow2 (32 - prefixLength);
      network = builtins.div (parseIPv4 address) hostCount * hostCount;
    in
    assert length parts == 2;
    assert prefixLength >= 0 && prefixLength <= 32;
    {
      inherit address prefixLength hostCount network;
      broadcast = network + hostCount - 1;
      cidr = "${renderIPv4 network}/${toString prefixLength}";
    };

  addToIPv4 = ip: delta: renderIPv4 (parseIPv4 ip + delta);

  netmaskPrefixBits = {
    "0" = 0;
    "128" = 1;
    "192" = 2;
    "224" = 3;
    "240" = 4;
    "248" = 5;
    "252" = 6;
    "254" = 7;
    "255" = 8;
  };

  prefixFromNetmask =
    netmask:
    let
      octets = splitString "." netmask;
      prefixBits = map (octet: netmaskPrefixBits.${octet} or (throw "Invalid IPv4 subnet mask octet `${octet}` in `${netmask}`")) octets;
      contiguousTail =
        let
          go =
            remaining: seenTail:
            if remaining == [ ] then
              true
            else
              let
                current = builtins.head remaining;
                rest = builtins.tail remaining;
              in
              if seenTail then
                current == 0 && go rest true
              else if current == 8 then
                go rest false
              else
                go rest true;
        in
        go prefixBits false;
    in
    assert length octets == 4;
    assert contiguousTail;
    builtins.foldl' (sum: bits: sum + bits) 0 prefixBits;

  sortById = builtins.sort (a: b: a.id < b.id);
  sortByAddress = builtins.sort (a: b: a.address < b.address);

  mkProvenance = moduleName: optionPath: {
    module = moduleName;
    path = optionPath;
    authority = "declarative";
  };

  routedSubnetEntries = mapAttrsToList (
    name: iface:
    let
      parsed = parseCidr iface.ipv4Address;
      dhcpIface = routerDhcpEffectiveInterfaces.${name} or null;
    in
    {
      id = "routed:${name}";
      key = name;
      label = name;
      cidr = parsed.cidr;
      gatewayAddress = parsed.address;
      interface = {
        device = iface.device;
        role = iface.role;
      };
      dnsServers = iface.dns or [ ];
      searchDomains = iface.domains or [ ];
      dhcpBackend = if dhcpIface != null then "router-dhcp" else null;
      dynamicPools =
        if dhcpIface != null then
          [
            {
              start = renderIPv4 (parsed.network + dhcpIface.poolOffset);
              end = renderIPv4 (parsed.network + dhcpIface.poolOffset + dhcpIface.poolSize - 1);
            }
          ]
        else
          [ ];
      provenance = [
        (mkProvenance "router-networking" "services.router-networking.routedInterfaces.${name}")
      ];
    }
  ) routedInterfaces;

  keaSubnetEntries =
    if hasRouterKea && (config.services.router-kea.enable or false) then
      [
        {
          id = "kea:dhcp4";
          key = "kea-dhcp4";
          label = "kea-dhcp4";
          cidr = config.services.router-kea.dhcp4.subnet;
          gatewayAddress = config.services.router-kea.dhcp4.gatewayAddress;
          interface = null;
          dnsServers = config.services.router-kea.dhcp4.dnsServers;
          searchDomains = config.services.router-kea.dhcp4.searchDomains;
          dhcpBackend = "kea";
          dynamicPools = map (pool: {
            start = pool.start;
            end = pool.end;
          }) config.services.router-kea.dhcp4.poolRanges;
          provenance = [
            (mkProvenance "router-kea" "services.router-kea.dhcp4")
          ];
        }
      ]
    else
      [ ];

  technitiumSubnetEntries =
    if hasRouterTechnitium && (config.services.router-technitium.enable or false) then
      mapAttrsToList (
        name: scope:
        let
          prefixLength = prefixFromNetmask scope.subnetMask;
          cidr = parseCidr "${scope.startingAddress}/${toString prefixLength}".cidr;
        in
        {
          id = "technitium:${name}";
          key = name;
          label = name;
          inherit cidr;
          gatewayAddress = scope.routerAddress;
          interface = null;
          dnsServers = scope.dnsServers;
          searchDomains =
            optional (scope.domainName != null) scope.domainName
            ++ scope.domainSearchList;
          dhcpBackend = "technitium";
          dynamicPools = [
            {
              start = scope.startingAddress;
              end = scope.endingAddress;
            }
          ];
          provenance = [
            (mkProvenance "router-technitium" "services.router-technitium.scopes.${name}")
          ];
        }
      ) (config.services.router-technitium.scopes or { })
    else
      [ ];

  inventorySubnets = sortById (routedSubnetEntries ++ keaSubnetEntries ++ technitiumSubnetEntries);

  subnetIdForAddress =
    address:
    let
      ipInt = parseIPv4 address;
      matches = filter (
        subnet:
        let
          parsed = parseCidr subnet.cidr;
        in
        ipInt >= parsed.network && ipInt <= parsed.broadcast
      ) inventorySubnets;
      routedMatches = filter (subnet: strings.hasPrefix "routed:" subnet.id) matches;
    in
    if routedMatches != [ ] then
      (builtins.head routedMatches).id
    else if matches != [ ] then
      (builtins.head matches).id
    else
      null;

  routerDhcpReservations =
    if hasRouterDhcp && (routerDhcpCfg.enable or false) then
      flatten (mapAttrsToList (
        ifaceName: ifaceCfg:
        map (
          lease:
          {
            id = "router-dhcp:${ifaceName}:${lease.address}";
            label = if lease.hostname != null then lease.hostname else lease.address;
            hostname = lease.hostname;
            ipv4Address = lease.address;
            macAddress = lease.macAddress;
            subnetRef = subnetIdForAddress lease.address;
            sourceKind = "router-dhcp-static-lease";
            provenance = [
              (mkProvenance "router-dhcp" "services.router-dhcp.interfaces.${ifaceName}.staticLeases")
            ];
          }
        ) ifaceCfg.staticLeases
      ) routerDhcpEffectiveInterfaces)
    else
      [ ];

  keaReservations =
    if hasRouterKea && (config.services.router-kea.enable or false) then
      map (
        reservation:
        {
          id = "kea:${reservation.ip-address}";
          label = if reservation.hostname != null then reservation.hostname else reservation.ip-address;
          hostname = reservation.hostname;
          ipv4Address = reservation.ip-address;
          macAddress = reservation.hw-address;
          subnetRef = subnetIdForAddress reservation.ip-address;
          sourceKind = "kea-reservation";
          provenance = [
            (mkProvenance "router-kea" "services.router-kea.dhcp4.reservations")
          ];
        }
      ) config.services.router-kea.dhcp4.reservations
    else
      [ ];

  technitiumReservations =
    if hasRouterTechnitium && (config.services.router-technitium.enable or false) then
      mapAttrsToList (
        name: reservation:
        {
          id = "technitium:${name}";
          label =
            if reservation.hostName != null then
              reservation.hostName
            else
              name;
          hostname = reservation.hostName;
          ipv4Address = reservation.ipAddress;
          macAddress = reservation.macAddress;
          subnetRef = subnetIdForAddress reservation.ipAddress;
          sourceKind = "technitium-reservation";
          provenance = [
            (mkProvenance "router-technitium" "services.router-technitium.dhcpReservations.${name}")
          ];
        }
      ) (config.services.router-technitium.dhcpReservations or { })
    else
      [ ];

  inventoryHosts = sortById (routerDhcpReservations ++ keaReservations ++ technitiumReservations);

  inventoryReservedAddresses = sortByAddress (map (
    host:
    {
      address = host.ipv4Address;
      label = host.label;
      hostRef = host.id;
      subnetRef = host.subnetRef;
      sourceKind = host.sourceKind;
      provenance = host.provenance;
    }
  ) inventoryHosts);

  inventoryArtifact = pkgs.writeText "router-dashboard-inventory.json" (
    builtins.toJSON {
      schemaVersion = 1;
      authoritative = false;
      authoritySurface = "declarative-router-config";
      notes = [
        "This artifact is a read-only reduction of declarative router state."
        "Runtime lease and reconciliation overlays belong in separate dashboard surfaces."
      ];
      subnets = inventorySubnets;
      hosts = inventoryHosts;
      reservedAddresses = inventoryReservedAddresses;
    }
  );

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

  effectiveVpnServices =
    optionals
      (
        hasRouterOption [ "services" "router-wireguard" "enable" ]
        && (config.services.router-wireguard.enable or false)
      )
      [
        {
          kind = "wireguard";
          name = config.services.router-wireguard.interfaceName;
          systemdUnit = "wireguard-${config.services.router-wireguard.interfaceName}";
          interface = config.services.router-wireguard.interfaceName;
        }
      ]
    ++ optionals (hasRouterOption [ "services" "router-openvpn" "instances" ]) (
      mapAttrsToList
        (name: instance: {
          kind = "openvpn";
          name = name;
          systemdUnit = "openvpn-${name}";
          interface = instance.interfaceName;
        })
        (config.services.router-openvpn.instances or { })
    )
    ++ optionals
      (
        hasRouterOption [ "services" "router-tailscale" "enable" ]
        && (config.services.router-tailscale.enable or false)
      )
      [
        {
          kind = "tailscale";
          name = "tailscale";
          systemdUnit = "tailscaled";
          interface = config.services.router-tailscale.interfaceName;
        }
      ]
    ++ optionals
      (
        hasRouterOption [ "services" "router-headscale" "enable" ]
        && (config.services.router-headscale.enable or false)
      )
      [
        {
          kind = "headscale";
          name = "headscale";
          systemdUnit = "headscale";
          interface = null;
        }
      ]
    ++ optionals
      (
        hasRouterOption [ "services" "router-netbird" "enable" ]
        && (config.services.router-netbird.enable or false)
      )
      [
        {
          kind = "netbird";
          name = config.services.router-netbird.clientName;
          systemdUnit = "netbird-${config.services.router-netbird.clientName}";
          interface = config.services.router-netbird.interfaceName;
        }
      ]
    ++ optionals
      (
        hasRouterOption [ "services" "router-zerotier" "enable" ]
        && (config.services.router-zerotier.enable or false)
      )
      [
        {
          kind = "zerotier";
          name = "zerotier";
          systemdUnit = "zerotierone";
          interface = config.services.router-zerotier.interfaceName;
        }
      ];

  effectiveTunnels =
    optionals
      (
        hasRouterOption [ "services" "router-tunnels" "tunnels" ]
        && hasRouterOption [ "services" "router-tunnels" "enable" ]
        && (config.services.router-tunnels.enable or false)
      )
      (map (tunnel: {
        provider = tunnel.provider;
        name = tunnel.name;
        systemdUnit = tunnel.systemdUnit;
        publicUrl = tunnel.publicUrl;
        description = tunnel.description;
      }) (config.services.router-tunnels.tunnels or [ ]));

  effectiveRemoteAdmin =
    optionals
      (
        hasRouterOption [ "services" "router-remote-admin" "entries" ]
        && hasRouterOption [ "services" "router-remote-admin" "enable" ]
        && (config.services.router-remote-admin.enable or false)
      )
      (map (entry: {
        kind = entry.kind;
        name = entry.name;
        systemdUnit = entry.systemdUnit;
        url = entry.url;
        description = entry.description;
      }) (config.services.router-remote-admin.entries or [ ]));

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
        vpnServices: ${builtins.toJSON effectiveVpnServices},
        tunnels: ${builtins.toJSON effectiveTunnels},
        remoteAdmin: ${builtins.toJSON effectiveRemoteAdmin},
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

  config = mkMerge [
    (mkIf cfg.enable {
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
          DASHBOARD_SERVICES = builtins.toJSON (cfg.services ++
            optional (config.services.router-nat64.enable or false) "tayga" ++
            optional (config.services.router-dns64.enable or false) "unbound" ++
            optional (config.services.router-mdns.enable or false) "avahi-daemon" ++
            optional (config.services.router-upnp.enable or false) "miniupnpd" ++
            optional (config.services.router-bgp.enable or false) "frr"
          );
          DASHBOARD_VPNS = builtins.toJSON effectiveVpnServices;
          DASHBOARD_TUNNELS = builtins.toJSON effectiveTunnels;
          DASHBOARD_REMOTE_ADMIN = builtins.toJSON effectiveRemoteAdmin;
          DASHBOARD_WOL_DEVICES = builtins.toJSON cfg.wakeOnLan.devices;
          DASHBOARD_INVENTORY_FILE = "${inventoryArtifact}";
          DASHBOARD_NAT64_PREFIX = if config.services.router-nat64.enable or false then config.services.router-nat64.ipv6Prefix else "";
          DASHBOARD_NAT64_POOL = if config.services.router-nat64.enable or false then config.services.router-nat64.ipv4Pool else "";
          TECHNITIUM_URL = "http://localhost:5380";
          TECHNITIUM_RUNTIME_API_KEY_FILE = technitiumRuntimeApiTokenPath;
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
          # PrivateUsers omitted: conflicts with AmbientCapabilities on non-root users.
          # The dedicated service user + CapabilityBoundingSet already provide isolation.

          # Network capabilities: CAP_NET_ADMIN for interface stats, CAP_NET_RAW for ping.
          # CAP_SETUID/CAP_SETGID are needed for the narrowly-scoped sudo path used
          # to query fail2ban-client status.
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SETUID" "CAP_SETGID" ];
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SETUID" "CAP_SETGID" ];

          # Read-only paths we need access to
          ReadOnlyPaths = [
            "/proc"
            "/sys/class/net"
            "/var/log/journal"
            "/run/agenix"
          ] ++ lib.optional (config.services.router-technitium.enable or false) technitiumRuntimeApiTokenPath;
        };

        path = with pkgs; [
          iproute2
          procps
          conntrack-tools
          nftables
          coreutils
          systemd
          iputils # for ping
          fail2ban
          speedtest-cli # for speed tests
          wireguard-tools # for WireGuard peer status
          "/run/wrappers" # for sudo wrapper
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
    })

    # Auto-open dashboard port in router-firewall when both are enabled
    (optionalAttrs (
      hasRouterOption [ "services" "router-firewall" "enable" ]
      && hasRouterOption [ "services" "router-firewall" "trustedTcpPorts" ]
    ) (
      mkIf (cfg.enable && (config.services.router-firewall.enable or false)) {
        services.router-firewall.trustedTcpPorts = [ cfg.port ];
      }
    ))
  ];
}
