{
  self,
  lib,
  eval,
  ...
}:

{
  router-slices-eval = eval.mkNixosEvalCheck "router-slices-eval" [
    self.nixosModules.default
    {
      services.router-slices.enable = true;
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.systemd.slices."router-core".sliceConfig.OOMScoreAdjust == -900;
          message = "router-core.slice should have OOMScoreAdjust = -900";
        }
        {
          assertion = config.systemd.slices."router-core".sliceConfig.CPUWeight == 1000;
          message = "router-core.slice should have CPUWeight = 1000";
        }
        {
          assertion = config.systemd.slices."router-observability".sliceConfig.MemoryMax == "256M";
          message = "router-observability.slice should have MemoryMax = 256M";
        }
        {
          assertion = config.systemd.slices."router-observability".sliceConfig.CPUQuota == "30%";
          message = "router-observability.slice should have CPUQuota = 30%";
        }
        {
          assertion = config.systemd.slices."router-applications".sliceConfig.MemoryMax == "512M";
          message = "router-applications.slice should have MemoryMax = 512M";
        }
        {
          assertion = config.systemd.slices."router-applications".sliceConfig.CPUQuota == "50%";
          message = "router-applications.slice should have CPUQuota = 50%";
        }
        {
          assertion = config.systemd.services.systemd-networkd.serviceConfig.Slice == "router-core.slice";
          message = "systemd-networkd should be in router-core.slice";
        }
        {
          assertion = config.systemd.services.ulogd.serviceConfig.Slice == "router-observability.slice";
          message = "ulogd should be in router-observability.slice";
        }
        {
          assertion = config.systemd.services.caddy.serviceConfig.Slice == "router-applications.slice";
          message = "caddy should be in router-applications.slice";
        }
      ];
    })
  ];
}
