{
  self,
  eval,
  ...
}:

{
  # INVARIANT: upstream runs pangolin as `pangolin` with ProtectSystem=full,
  # so /etc/pangolin must be created by a privileged ExecStartPre and listed in
  # ReadWritePaths,
  # or preStart fails on a fresh host (docs/router-pangolin.md).
  router-pangolin-etc-dir-eval = eval.mkNixosEvalCheck "router-pangolin-etc-dir" [
    self.nixosModules.router-pangolin
    {
      services.router-pangolin = {
        enable = true;
        baseDomain = "example.com";
        dashboardDomain = "pangolin.example.com";
        letsEncryptEmail = "admin@example.com";
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion =
            let pre = config.systemd.services.pangolin.serviceConfig.ExecStartPre;
            in builtins.isList pre && pre != [ ] && builtins.substring 0 1 (toString (builtins.head pre)) == "+"
              && builtins.match ".*pangolin-etc-dir.*" (toString (builtins.head pre)) != null;
          message = "router-pangolin must create /etc/pangolin in a privileged ExecStartPre that runs first.";
        }
        {
          assertion = builtins.elem "-/etc/pangolin" config.systemd.services.pangolin.serviceConfig.ReadWritePaths;
          message = "router-pangolin must make /etc/pangolin writable to the sandboxed service.";
        }
        {
          # fosrl/gerbil#51: < 1.5.2 panics on every stop and the unit fails.
          assertion =
            let
              exec = config.systemd.services.gerbil.serviceConfig.ExecStart;
              pkg = config.services.router-pangolin.gerbilPackage;
            in
            builtins.compareVersions pkg.version "1.5.2" >= 0
            && exec == builtins.concatStringsSep " " (map (a: "\"${a}\"") [
              "${pkg}/bin/gerbil"
              "--reachableAt=http://localhost:3004"
              "--generateAndSaveKeyTo=/var/lib/pangolin/config/key"
              "--remoteConfig=http://localhost:3005/api/v1/gerbil/get-config"
            ]);
          message = "router-pangolin must run gerbil >= 1.5.2 with the nixpkgs module's arguments.";
        }
        {
          assertion = config.systemd.services.pangolin.serviceConfig.User == "pangolin";
          message = "router-pangolin's /etc/pangolin ownership assumes the service runs as pangolin.";
        }
        {
          # Pangolin 1.24's AI gateway defaulted onto internal_port (3005).
          assertion =
            let
              server = config.services.pangolin.settings.server;
              ports = map (key: server.${key}) [ "internal_port" "ai_gateway_port" ];
            in
            builtins.length ports == builtins.length (builtins.attrNames (builtins.listToAttrs (map (p: { name = toString p; value = null; }) ports)));
          message = "router-pangolin's internal_port and ai_gateway_port must differ.";
        }
      ];
    })
  ];
}
