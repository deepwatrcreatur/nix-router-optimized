{
  self,
  lib,
  eval,
}:

# router-observability: Vector runs only when ulogd writes JSON, and saying
# otherwise warns instead of silently doing nothing.
let
  base = { services.router-observability.enable = true; };
in
{
  router-observability-vector-follows-plugin-eval = eval.mkNixosEvalCheck "router-observability-vector-follows-plugin" [
    self.nixosModules.router-observability
    base
    ({ config, ... }: {
      assertions = [
        {
          assertion = !config.services.router-observability.enableVector && !config.services.vector.enable;
          message = "With the default logemu output, enableVector must default to false and Vector must not run.";
        }
        {
          assertion = lib.all (w: !(lib.hasInfix "enableVector" w)) config.warnings;
          message = "The default configuration must not warn about Vector.";
        }
      ];
    })
  ];

  router-observability-vector-json-eval = eval.mkNixosEvalCheck "router-observability-vector-json" [
    self.nixosModules.router-observability
    base
    { services.router-observability.ulogdOutputPlugin = "json"; }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.router-observability.enableVector && config.services.vector.enable;
          message = "With ulogdOutputPlugin = json, Vector must be enabled by default.";
        }
      ];
    })
  ];

  router-observability-vector-logemu-warns-eval = eval.mkNixosEvalCheck "router-observability-vector-logemu-warns" [
    self.nixosModules.router-observability
    base
    { services.router-observability.enableVector = true; }
    ({ config, ... }: {
      assertions = [
        {
          assertion = !config.services.vector.enable;
          message = "Vector cannot run on logemu output.";
        }
        {
          assertion = lib.any (lib.hasInfix "enableVector is set, but Vector only") config.warnings;
          message = "Forcing enableVector with logemu output must warn.";
        }
      ];
    })
  ];
}
