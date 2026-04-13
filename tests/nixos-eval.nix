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

  mkNixosEvalFailureCheck =
    name: modules:
    let
      result = builtins.tryEval (
        builtins.deepSeq
          ((nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              baseModule
            ] ++ modules;
          }).config.system.build.toplevel.drvPath)
          true
      );
    in
    pkgs.runCommand "router-${name}-eval-fails" { } ''
      if ${if result.success then "true" else "false"}; then
        echo "expected NixOS evaluation for ${lib.escapeShellArg name} to fail, but it succeeded" >&2
        exit 1
      fi

      echo "evaluation failed as expected" > "$out"
    '';
in
{
  inherit mkNixosEvalCheck mkNixosEvalFailureCheck;
}
