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
}
