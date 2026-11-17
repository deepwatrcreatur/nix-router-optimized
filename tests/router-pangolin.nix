{
  self,
  eval,
  ...
}:

{
  # INVARIANT: upstream runs pangolin as `pangolin` with ProtectSystem=full,
  # so /etc/pangolin must be created by tmpfiles and listed in ReadWritePaths,
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
          assertion = builtins.elem "d /etc/pangolin 0750 pangolin fossorial -" config.systemd.tmpfiles.rules;
          message = "router-pangolin must create /etc/pangolin owned by pangolin via tmpfiles.";
        }
        {
          assertion = builtins.elem "/etc/pangolin" config.systemd.services.pangolin.serviceConfig.ReadWritePaths;
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
