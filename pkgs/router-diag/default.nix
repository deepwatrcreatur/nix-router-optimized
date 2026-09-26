{ pkgs }:

let
  routerctlBin = pkgs.writers.writePython3Bin "routerctl" {
    flakeIgnore = [ "E501" "E265" "E302" "E305" ];
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (pkgs.lib.makeBinPath [
        pkgs.iproute2
        pkgs.nftables
        pkgs.wireguard-tools
        pkgs.systemd
        pkgs.gnugrep
        pkgs.gawk
        pkgs.ethtool
        pkgs.coreutils
      ])
    ];
  } (builtins.readFile ./routerctl.py);
in
pkgs.runCommand "routerctl" {
  meta = {
    description = "Operational Diagnostics CLI and Policy Explainer for NixOS Router";
    mainProgram = "routerctl";
  };
} ''
  mkdir -p $out/bin
  ln -s ${routerctlBin}/bin/routerctl $out/bin/routerctl
  ln -s ${routerctlBin}/bin/routerctl $out/bin/router-diag
''
