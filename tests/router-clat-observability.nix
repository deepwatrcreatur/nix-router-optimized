{
  self,
  lib,
  eval,
  ...
}:

{
  router-clat-dashboard-metadata-eval = eval.mkNixosEvalCheck "router-clat-dashboard-metadata" [
    self.nixosModules.router-clat
    self.nixosModules.router-dashboard
    {
      services.router-clat = {
        enable = true;
        upstreamInterface = "wan0";
        listenInterfaces = [ "lan0" "lan1" ];
      };

      services.router-dashboard.enable = true;
    }
    ({ config, ... }:
      let
        clat = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_CLAT;
      in
      {
        assertions = [
          {
            assertion =
              clat.enabled
              && clat.backend == "tayga"
              && clat.systemdUnit == "router-clat-tayga"
              && clat.translationInterface == "clat0";
            message = "router-dashboard should export bounded router-clat runtime metadata.";
          }
          {
            assertion =
              clat.operatorBoundary.ha == "non-ha"
              && clat.operatorBoundary.ownership == "single-owner";
            message = "router-dashboard should surface router-clat non-HA/single-owner boundary metadata.";
          }
        ];
      })
  ];

  router-clat-rendered-tayga-conf-eval = eval.mkNixosEvalCheck "router-clat-rendered-tayga-conf" [
    self.nixosModules.router-clat
    {
      services.router-clat = {
        enable = true;
        upstreamInterface = "wan0";
        listenInterfaces = [ "lan0" ];
        legacyIpv4Pool = "100.64.46.0/24";
        mappingPrefix6 = "fd46:ca17:1::/96";
      };
    }
    ({ config, ... }:
      let
        taygaConf = builtins.readFile config.environment.etc."router-clat/tayga.conf".source;
      in
      {
        assertions = [
          {
            assertion =
              lib.hasInfix "tun-device clat0" taygaConf
              && lib.hasInfix "dynamic-pool 100.64.46.0/24" taygaConf
              && lib.hasInfix "prefix fd46:ca17:1::/96" taygaConf;
            message = "router-clat should render an inspectable tayga.conf with the declared runtime pool and prefix.";
          }
          {
            assertion = lib.hasInfix "data-dir /var/lib/router-clat" taygaConf;
            message = "router-clat should render the runtime state directory into tayga.conf.";
          }
        ];
      })
  ];
}
