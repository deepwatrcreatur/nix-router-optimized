{
  self,
  eval,
  lib,
  ...
}:

let
  findById = id: items: builtins.filter (item: item.id == id) items;
  findByAddress = address: items: builtins.filter (item: item.address == address) items;
  dashboardIndex = builtins.readFile ../modules/router-dashboard/index.html;
  dashboardMain = builtins.readFile ../modules/router-dashboard/js/main.js;
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
      in
      {
        assertions = [
          {
            assertion = inventory.schemaVersion == 1;
            message = "router-dashboard inventory export should declare schema version 1.";
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
      ];
    }
  ];
}
