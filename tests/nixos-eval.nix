{
  lib,
  pkgs,
  nixpkgs,
  system,
}:

let
  baseModule = {
    networking.hostName = "router-check";
    system.stateVersion = "25.11";
    nixpkgs.config.allowUnfree = true;

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    boot.loader.grub.devices = [ "nodev" ];
  };

  mkNixosEvalCheck =
    name: modules:
    let
      toplevel = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
        ] ++ modules;
      }).config.system.build.toplevel;
    in
    pkgs.runCommand "router-${name}-eval" { } ''
      echo ${lib.escapeShellArg toplevel.drvPath} > "$out"
    '';
in
{
  inherit mkNixosEvalCheck;
}
