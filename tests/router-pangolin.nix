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
          assertion = config.systemd.services.pangolin.serviceConfig.User == "pangolin";
          message = "router-pangolin's /etc/pangolin ownership assumes the service runs as pangolin.";
        }
      ];
    })
  ];
}
