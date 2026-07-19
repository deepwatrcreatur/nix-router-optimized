{ pkgs, ... }:

{
  systemd.services.router-lab-owner-demo = {
    description = "Lab-only single-active ownership demo service";
    wantedBy = [ ];
    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "router-lab-owner-demo";
      ExecStart = "${pkgs.bash}/bin/bash -lc 'echo started > /run/router-lab-owner-demo/state; exec ${pkgs.coreutils}/bin/sleep infinity'";
      Restart = "always";
      RestartSec = "1s";
    };
  };
}
