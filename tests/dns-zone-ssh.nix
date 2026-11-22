{
  self,
  lib,
  eval,
}:

# dns-zone writes SSH client entries only for hosts that opt in, and never for
# the zone apex.
{
  dns-zone-ssh-opt-in-eval = eval.mkNixosEvalCheck "dns-zone-ssh-opt-in" [
    self.nixosModules.dns-zone
    {
      services.router.dnsZones."example.test" = {
        nameserverIP = "10.0.0.1";
        staticHosts = {
          gateway = {
            ipAddress = "10.0.0.1";
            ssh = true;
          };
          doorbell.ipAddress = "10.0.0.50";
          "@" = {
            ipAddress = "10.0.0.1";
            ssh = true;
          };
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix "Host gateway.example.test" config.programs.ssh.extraConfig;
          message = "A host with ssh = true must get an SSH client entry.";
        }
        {
          assertion = !(lib.hasInfix "doorbell" config.programs.ssh.extraConfig);
          message = "Hosts must not get SSH client entries by default.";
        }
        {
          assertion = !(lib.hasInfix "Host @." config.programs.ssh.extraConfig);
          message = "The zone apex must never get an SSH client entry.";
        }
      ];
    })
  ];
}
