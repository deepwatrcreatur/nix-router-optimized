{ pkgs }:

pkgs.writeShellApplication {
  name = "router-diag";
  
  runtimeInputs = with pkgs; [
    iproute2
    gnugrep
    gawk
    nftables
    wireguard-tools
    systemd
  ];

  text = builtins.readFile ./router-diag.sh;
}
