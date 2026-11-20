{ writeShellApplication, coreutils, diffutils, gnugrep, systemd, nix, util-linux }:

writeShellApplication {
  name = "router-apply";
  runtimeInputs = [ coreutils diffutils gnugrep systemd nix util-linux ];
  text = builtins.readFile ./router-apply.sh;
  meta = {
    description = "Commit-confirm style switching for NixOS routers: trial, auto-revert, confirm";
    mainProgram = "router-apply";
  };
}
