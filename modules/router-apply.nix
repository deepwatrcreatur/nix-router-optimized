{ config, lib, pkgs, ... }:

let
  cfg = config.services.router-apply;
in
{
  options.services.router-apply = {
    enable = lib.mkEnableOption ''
      `router-apply`, a commit-confirm style deploy helper: it activates a new
      system for a trial and returns to the previous one unless the operator
      runs `router-apply confirm` in time. See docs/router-apply-safety.md'';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/router-apply { };
      defaultText = lib.literalExpression "pkgs.callPackage ../pkgs/router-apply { }";
      description = "The router-apply package.";
    };

    defaultTimeoutSec = lib.mkOption {
      type = lib.types.ints.between 10 86400;
      default = 300;
      description = "Seconds before an unconfirmed trial is reverted, unless `--timeout` is given.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.symlinkJoin {
        name = "router-apply-wrapped";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/router-apply \
            --set-default ROUTER_APPLY_DEFAULT_TIMEOUT ${toString cfg.defaultTimeoutSec}
        '';
      })
    ];
  };
}
