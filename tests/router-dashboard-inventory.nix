{
  self,
  eval,
  lib,
  pkgs,
  ...
}:

let
  findById = id: items: builtins.filter (item: item.id == id) items;
  findByAddress = address: items: builtins.filter (item: item.address == address) items;
  dashboardIndex = builtins.readFile ../modules/router-dashboard/index.html;
  dashboardMain = builtins.readFile ../modules/router-dashboard/js/main.js;
  inventoryWidget = builtins.readFile ../modules/router-dashboard/js/widgets/inventory-widget.js;
  dashboardCss = builtins.readFile ../modules/router-dashboard/css/dashboard.css;
in
{
  router-dashboard-inventory-router-dhcp-eval = eval.mkNixosEvalCheck "router-dashboard-inventory-router-dhcp" [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    self.nixosModules.router-dashboard
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.200.1/24";
          role = "lan";
          dns = [ "10.10.200.1" ];
          domains = [ "deepwatercreature.com" ];
        };
      };

      services.router-dhcp = {
        enable = true;
      };

      services.router-dashboard.enable = true;
    }
    ({ config, ... }:
      let
        inventory = builtins.fromJSON (
          builtins.readFile config.systemd.services.router-dashboard.environment.DASHBOARD_INVENTORY_FILE
        );
        routedLan = builtins.head (findById "routed:lan" inventory.subnets);
        findInterfaceById = id: builtins.head (builtins.filter (i: i.id == id) inventory.interfaces);
        findPrefixById = id: builtins.head (builtins.filter (p: p.id == id) inventory.prefixes);
        wanIface = findInterfaceById "wan:wan";
        lanIface = findInterfaceById "routed:lan";
        lanPrefix = findPrefixById "prefix:routed:lan";
        lanSegmentEdge = builtins.head (builtins.filter (e: e.id == "edge:segment:routed:lan") inventory.edges);
        wanUpstreamEdge = builtins.head (builtins.filter (e: e.id == "edge:upstream:wan:wan") inventory.edges);
      in
      {
        assertions = [
          {
            assertion = inventory.schemaVersion == 3;
            message = "router-dashboard inventory export should declare schema version 3.";
          }
          {
            assertion =
              routedLan.cidr == "10.10.200.0/24"
              && routedLan.gatewayAddress == "10.10.200.1"
              && routedLan.dhcpBackend == "router-dhcp";
            message = "router-dashboard inventory export should reduce routed subnets into canonical subnet records.";
          }
          {
            assertion =
              (builtins.head routedLan.dynamicPools).start == "10.10.200.100"
              && (builtins.head routedLan.dynamicPools).end == "10.10.200.199";
            message = "router-dashboard inventory export should derive router-dhcp dynamic pool bounds.";
          }
          {
            assertion = inventory.hosts == [ ] && inventory.reservedAddresses == [ ];
            message = "router-dashboard inventory export should stay empty for host/reservation records when router-dhcp has no declared static leases.";
          }
          {
            assertion = wanIface.device == "eth0" && wanIface.role == "wan";
            message = "router-dashboard inventory should export WAN interface entry.";
          }
          {
            assertion = lanIface.device == "eth1" && lanIface.role == "lan" && lanIface.subnetRefs == [ "routed:lan" ];
            message = "router-dashboard inventory should export routed interface entry with subnet refs.";
          }
          {
            assertion = lanPrefix.cidr == "10.10.200.0/24" && lanPrefix.interfaceRef == "routed:lan";
            message = "router-dashboard inventory should export prefix entry linked to its interface.";
          }
          {
            assertion =
              lanSegmentEdge.kind == "segment"
              && lanSegmentEdge.interfaceRef == "routed:lan"
              && lanSegmentEdge.prefixRef == "prefix:routed:lan";
            message = "router-dashboard inventory should export declared segment edges for prefixes.";
          }
          {
            assertion = wanUpstreamEdge.kind == "upstream" && wanUpstreamEdge.interfaceRef == "wan:wan";
            message = "router-dashboard inventory should export declared upstream edges for WAN interfaces.";
          }
        ];
      })
  ];

  router-dashboard-inventory-kea-eval = eval.mkNixosEvalCheck "router-dashboard-inventory-kea" [
    self.nixosModules.router-networking
    self.nixosModules.router-kea
    self.nixosModules.router-dashboard
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.210.1/24";
          role = "lan";
        };
      };

      services.router-kea = {
        enable = true;
        dhcp4 = {
          subnet = "10.10.210.0/24";
          gatewayAddress = "10.10.210.1";
          dnsServers = [ "10.10.210.1" ];
          searchDomains = [ "deepwatercreature.com" ];
          poolRanges = [
            {
              start = "10.10.210.100";
              end = "10.10.210.199";
            }
          ];
          reservations = [
            {
              hw-address = "11:22:33:44:55:66";
              ip-address = "10.10.210.20";
              hostname = "printer";
            }
          ];
        };
      };

      services.router-dashboard.enable = true;
    }
    ({ config, ... }:
      let
        inventory = builtins.fromJSON (
          builtins.readFile config.systemd.services.router-dashboard.environment.DASHBOARD_INVENTORY_FILE
        );
        keaSubnet = builtins.head (findById "kea:dhcp4" inventory.subnets);
        printerReservation = builtins.head (findById "kea:10.10.210.20" inventory.hosts);
        keaPrefix = builtins.head (builtins.filter (p: p.id == "prefix:kea:dhcp4") inventory.prefixes);
      in
      {
        assertions = [
          {
            assertion =
              keaSubnet.cidr == "10.10.210.0/24"
              && keaSubnet.dhcpBackend == "kea"
              && (builtins.head keaSubnet.dynamicPools).start == "10.10.210.100";
            message = "router-dashboard inventory export should include Kea declarative scope metadata.";
          }
          {
            assertion =
              printerReservation.label == "printer"
              && printerReservation.subnetRef == "routed:lan"
              && printerReservation.sourceKind == "kea-reservation";
            message = "router-dashboard inventory export should include Kea reservations as inventory hosts.";
          }
          {
            assertion = keaPrefix.cidr == "10.10.210.0/24" && keaPrefix.dhcpBackend == "kea";
            message = "router-dashboard inventory should export Kea prefix entry.";
          }
        ];
      })
  ];

  router-dashboard-inventory-browser-contract-eval = eval.mkNixosEvalCheck "router-dashboard-inventory-browser-contract" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard.enable = true;
    }
    {
      assertions = [
        {
          assertion =
            lib.hasInfix ''data-dashboard-tab="inventory"'' dashboardIndex
            && lib.hasInfix ''data-dashboard-page="inventory"'' dashboardIndex;
          message = "router-dashboard should expose a dedicated inventory page in the dashboard shell.";
        }
        {
          assertion =
            lib.hasInfix "InventoryWidget" dashboardMain
            && lib.hasInfix "'inventory'" dashboardMain;
          message = "router-dashboard main script should wire the inventory page into the page model.";
        }
        {
          assertion =
            lib.hasInfix ''data-inventory-view="edges"'' inventoryWidget
            && lib.hasInfix "renderEdgesView" inventoryWidget;
          message = "router-dashboard inventory browser should expose an edge relationship view.";
        }
      ];
    }
  ];

  router-dashboard-inventory-technitium-invalid-mask-fails = eval.mkNixosEvalFailureCheck "router-dashboard-inventory-technitium-invalid-mask" [
    self.nixosModules.router-technitium
    self.nixosModules.router-dashboard
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";

      services.router-technitium = {
        enable = true;
        scopes.lan = {
          startingAddress = "10.10.220.100";
          endingAddress = "10.10.220.199";
          subnetMask = "255.0.255.0";
          routerAddress = "10.10.220.1";
          dnsServers = [ "10.10.220.1" ];
        };
      };

      services.router-dashboard.enable = true;
    }
  ];

  router-dashboard-inventory-router-dhcp-invalid-pool-fails = eval.mkNixosEvalFailureCheck "router-dashboard-inventory-router-dhcp-invalid-pool" [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    self.nixosModules.router-dashboard
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        routedInterfaces.lan = {
          device = "eth1";
          ipv4Address = "10.10.230.1/24";
          role = "lan";
        };
      };

      services.router-dhcp = {
        enable = true;
        interfaces.lan = {
          poolOffset = 300;
          poolSize = 100;
        };
      };

      services.router-dashboard.enable = true;
    }
  ];

  router-dashboard-inventory-runtime-unit-tests = pkgs.runCommand "router-dashboard-inventory-runtime-unit-tests" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp ${self}/modules/router-dashboard/api/server.py server.py
    cp ${self}/modules/router-dashboard/api/test_inventory_runtime.py test_inventory_runtime.py
    python3 test_inventory_runtime.py -v
    touch $out
  '';

  # ── Light Theme Contract ───────────────────────────────────────────────────

  router-dashboard-light-theme-css-eval = eval.mkNixosEvalCheck "router-dashboard-light-theme-css" [
    self.nixosModules.router-networking
    self.nixosModules.router-dashboard
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
      };
      services.router-dashboard = {
        enable = true;
        theme = "light";
      };
    }
    ({ config, ... }:
    let
      staticDrv = config.systemd.services.router-dashboard.environment.DASHBOARD_STATIC or "";
    in {
      assertions = [
        {
          assertion = lib.hasInfix "data-theme" dashboardCss;
          message = "dashboard.css must contain data-theme selector for light theme.";
        }
        {
          assertion = lib.hasInfix "--bg-primary: #f8f5f0" dashboardCss;
          message = "dashboard.css must define light theme --bg-primary variable.";
        }
        {
          assertion = lib.hasInfix "--text-primary: #2c2014" dashboardCss;
          message = "dashboard.css must define light theme --text-primary variable.";
        }
        {
          assertion = config.systemd.services.router-dashboard.environment.DASHBOARD_THEME == "light";
          message = "DASHBOARD_THEME env var should be set to light.";
        }
      ];
    })
  ];
}
