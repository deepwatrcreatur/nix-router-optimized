{
  pkgs,
  lib,
  self,
}:

{
  name,
  nodes,
  testScript,
  extraConfig ? { },
  ...
}@args:

let
  baseNodeModule = {
    system.stateVersion = lib.mkDefault "25.11";
    networking.usePredictableInterfaceNames = lib.mkDefault false;
    virtualisation.memorySize = lib.mkDefault 1024;
    virtualisation.cores = lib.mkDefault 2;

    # Suppress default DHCP on eth0 (QEMU user-mode slirp network) so virtual test networks control routing
    systemd.network.networks."01-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "no";
      linkConfig.Unmanaged = true;
    };
  };
in
pkgs.testers.runNixOSTest (
  (builtins.removeAttrs args [ "extraConfig" "nodes" "testScript" ])
  // {
    inherit name testScript;

    nodes = lib.mapAttrs (
      nodeName: nodeDef:
      { lib, ... }:
      {
        imports = [
          baseNodeModule
          (if lib.isFunction nodeDef then nodeDef else (_: nodeDef))
          extraConfig
        ];
      }
    ) nodes;
  }
)
