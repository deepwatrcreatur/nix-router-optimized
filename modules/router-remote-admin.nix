{ config, lib, ... }:

with lib;

let
  cfg = config.services.router-remote-admin;

  entryModule = types.submodule ({ ... }: {
    options = {
      name = mkOption {
        type = types.str;
        description = "Short identifier for the remote admin entry (e.g., guac, mesh, ssh).";
      };

      kind = mkOption {
        type = types.enum [ "guacamole" "meshcentral" "ssh" "rdp" "vnc" "kvm" "idrac" "ilo" "other" ];
        description = "Remote administration tool backing this entry (Guacamole, MeshCentral, SSH, etc.).";
      };

      unit = mkOption {
        type = types.str;
        description = "Systemd unit name backing this entry (e.g., guacd.service, meshcentral.service).";
      };

      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Primary URL for this remote admin entry (e.g., https://guac.example/).";
      };

      description = mkOption {
        type = types.str;
        default = "";
        description = "Human-readable description of the remote admin entry (scope, environment, etc.).";
      };
    };
  });
in
{
  options.services.router-remote-admin = {
    enable = mkEnableOption "metadata for remote administration entry points exposed on the router dashboard";

    entries = mkOption {
      type = types.listOf entryModule;
      default = [ ];
      description = ''
        Declarative metadata for remote administration entry points to surface in
        the router dashboard. This module does not manage the underlying
        services; it only describes existing units for status display.
      '';
      example = [
        {
          name = "guac";
          kind = "guacamole";
          unit = "guacd.service";
          url = "https://guac.example.net";
          description = "Guacamole gateway for lab machines";
        }
      ];
    };
  };

  config = mkIf cfg.enable { };
}
