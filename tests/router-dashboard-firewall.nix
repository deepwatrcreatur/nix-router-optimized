{
  self,
  eval,
  lib,
  ...
}:

let
  dashboardMain = builtins.readFile ../modules/router-dashboard/js/main.js;
  firewallWidget = builtins.readFile ../modules/router-dashboard/js/widgets/firewall-widget.js;
in
{
  router-dashboard-firewall-browser-contract-eval = eval.mkNixosEvalCheck "router-dashboard-firewall-browser-contract" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard.enable = true;
    }
    {
      assertions = [
        {
          assertion =
            lib.hasInfix "FirewallWidget" dashboardMain
            && lib.hasInfix "'nftables'" dashboardMain
            && lib.hasInfix "/firewall/activity-summary" firewallWidget
            && lib.hasInfix "renderFlowtableDetail" firewallWidget
            && lib.hasInfix "renderChainRows" firewallWidget
            && lib.hasInfix "renderRuleRows" firewallWidget
            && lib.hasInfix "Recent Activity" firewallWidget
            && lib.hasInfix "Counter Rules" firewallWidget
            && lib.hasInfix "Hot Chains" firewallWidget
            && lib.hasInfix "Hot Rules" firewallWidget;
          message = "router-dashboard should expose bounded firewall hit-counter, flowtable detail, and recent security activity summary through the API and firewall widget contract.";
        }
      ];
    }
  ];

  router-dashboard-agenix-optional-eval = eval.mkNixosEvalCheck "router-dashboard-agenix-optional" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard.enable = true;
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion =
            builtins.elem "-/run/agenix" config.systemd.services.router-dashboard.serviceConfig.ReadOnlyPaths
            && !(builtins.elem "/run/agenix" config.systemd.services.router-dashboard.serviceConfig.ReadOnlyPaths);
          message = "router-dashboard must bind /run/agenix optionally (\"-/run/agenix\"); hosts without agenix otherwise fail with 226/NAMESPACE.";
        }
      ];
    })
  ];
}
