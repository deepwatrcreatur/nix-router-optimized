{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;
in
lib.evalModules {
  modules = [
    # Minimal NixOS modules needed for assertions and standard services
    "${pkgs.path}/nixos/modules/misc/assertions.nix"
    ./modules/router-technitium.nix
    ./modules/dns-zone.nix
    ./modules/dns-blocklists.nix
    {
      config._module.args = {
        inherit pkgs;
      };
      config.services.router-technitium = {
        enable = true;
        scopes.LAN = {
          startingAddress = "10.10.10.100";
          endingAddress = "10.10.10.200";
          subnetMask = "255.255.255.0";
        };
      };
      # Mock age secrets
      options.age.secrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          technitium-api-key.path = "/tmp/fake-key";
        };
      };
      # Mock other missing options
      options.services.resolved.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      options.environment.variables = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };
      options.environment.etc = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.systemd.services = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    }
  ];
}
