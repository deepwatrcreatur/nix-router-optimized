{
  config,
  lib,
  pkgs,
  options,
  ...
}:

with lib;

let
  cfg = config.services.router-twingate;
  hasRouterOption = path: hasAttrByPath path options;
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
in
{
  options.services.router-twingate = {
    enable = mkEnableOption "router-aware Twingate connector/client integration";

    package = mkOption {
      type = types.package;
      default = pkgs.twingate;
      defaultText = literalExpression "pkgs.twingate";
      description = "The twingate package to use.";
    };

    trustedInterface = mkOption {
      type = types.bool;
      default = true;
      description = "Treat Twingate overlay interfaces as trusted in router-firewall.";
    };
  };

  config = mkIf cfg.enable {
    services.twingate = {
      enable = true;
      package = cfg.package;
    };
  };
}
