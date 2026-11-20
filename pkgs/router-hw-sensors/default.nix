{ writeShellApplication, coreutils, gawk, gnugrep, gnused, ethtool, mstflint }:

writeShellApplication {
  name = "router-hw-sensors";
  runtimeInputs = [ coreutils gawk gnugrep gnused ethtool mstflint ];
  text = builtins.readFile ./router-hw-sensors.sh;
  meta.description = "NIC ASIC and SFP sensor readings as node_exporter textfile metrics";
}
