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
        services = builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_SERVICES;
        statusFile = config.systemd.services.router-dashboard.environment.DASHBOARD_CLAT_STATUS_FILE;
      in
      {
        assertions = [
          {
            assertion =
              builtins.elem "router-clat-tayga" services
              && builtins.elem "router-clat-dns" services;
            message = "router-dashboard should include CLAT services in the monitored service list.";
          }
          {
            assertion = statusFile == "/run/router-clat/status.json";
            message = "router-dashboard should export the CLAT status file path for the dashboard API.";
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
