{
  self,
  eval,
  lib,
  pkgs,
  ...
}:

let
  servicesWidget = builtins.readFile ../modules/router-dashboard/js/widgets/services-widget.js;
in
{
  router-dashboard-service-control-config-eval = eval.mkNixosEvalCheck "router-dashboard-service-control-config" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard = {
        enable = true;
        mutationAuth.tokenFile = "/run/agenix/router-dashboard-mutation-token";
        services = [ "caddy" "grafana" ];
        serviceControl.services = [
          { name = "caddy"; }
        ];
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion =
            config.systemd.services.router-dashboard.environment.DASHBOARD_MUTATION_AUTH_TOKEN_FILE
            == "/run/agenix/router-dashboard-mutation-token";
          message = "router-dashboard should export the runtime mutation token file path.";
        }
        {
          assertion =
            builtins.fromJSON config.systemd.services.router-dashboard.environment.DASHBOARD_SERVICE_CONTROL_SERVICES
            == [
              {
                name = "caddy";
                unit = "caddy.service";
                allowedActions = [ "restart" ];
              }
            ];
          message = "router-dashboard should export a normalized restart-only service-control allowlist.";
        }
        {
          assertion = lib.elem "/run/agenix/router-dashboard-mutation-token" config.systemd.services.router-dashboard.serviceConfig.ReadOnlyPaths;
          message = "router-dashboard should be allowed to read the runtime mutation token file.";
        }
      ];
    })
  ];

  router-dashboard-service-control-requires-token-fails-eval = eval.mkNixosEvalFailureCheck "router-dashboard-service-control-requires-token" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard = {
        enable = true;
        services = [ "caddy" ];
        serviceControl.services = [
          { name = "caddy"; }
        ];
      };
    }
  ];

  router-dashboard-service-control-monitored-service-fails-eval = eval.mkNixosEvalFailureCheck "router-dashboard-service-control-monitored-service" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard = {
        enable = true;
        mutationAuth.tokenFile = "/run/agenix/router-dashboard-mutation-token";
        services = [ "grafana" ];
        serviceControl.services = [
          { name = "caddy"; }
        ];
      };
    }
  ];

  router-dashboard-service-control-browser-contract-eval = eval.mkNixosEvalCheck "router-dashboard-service-control-browser-contract" [
    self.nixosModules.router-dashboard
    {
      services.router-dashboard.enable = true;
    }
    {
      assertions = [
        {
          assertion =
            lib.hasInfix "service-control-panel" servicesWidget
            && lib.hasInfix "fetchMutationAPI('/services/control'" servicesWidget;
          message = "router-dashboard services widget should expose the authenticated restart control surface.";
        }
      ];
    }
  ];

  router-dashboard-service-control-unit-tests = pkgs.runCommand "router-dashboard-service-control-unit-tests" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp ${self}/modules/router-dashboard/api/server.py server.py
    cp ${self}/modules/router-dashboard/api/test_service_control.py test_service_control.py
    python3 test_service_control.py -v
    touch $out
  '';
}
