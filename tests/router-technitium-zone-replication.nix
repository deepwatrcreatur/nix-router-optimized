{
  self,
  lib,
  eval,
}:

let
  ageSecretStub = {
    options.age.secrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.path = lib.mkOption {
          type = lib.types.str;
        };
      });
      default = { };
    };
  };
  base = [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-admin-password.path = "/run/agenix/technitium-admin-password";
      services.router-technitium = {
        enable = true;
        bootstrapPasswordSecretName = "technitium-admin-password";
      };
    }
  ];
  # Reads the generated script (IFD) referenced by a unit's script text.
  # GOTCHA: builtins.match drops string context; restore it from the
  # script's context so pure evaluation may read the store path.
  unitScript =
    config: unit: name:
    let
      text = config.systemd.services.${unit}.script;
      path = builtins.head (builtins.match ".*(/nix/store/[a-z0-9]+-${name}).*" text);
      drv = lib.findFirst (d: lib.hasSuffix "-${name}.drv" d) (throw "no ${name} derivation") (
        builtins.attrNames (builtins.getContext text)
      );
    in
    builtins.readFile (builtins.appendContext path { ${drv}.outputs = [ "out" ]; });
in
{
  router-technitium-zone-replication-secondary-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-secondary"
      (base ++ [
        {
          # Stub for the dns-zone sync unit that creates declared zones.
          systemd.services.technitium-sync-static-hosts.script = "true";
          services.router-technitium.zoneReplication = {
            tsigKeyFile = "/run/secrets/zone-transfer";
            secondary = {
              zones = [ { name = "home.example"; } ];
              primaryAddresses = [ "10.10.10.1" ];
            };
          };
        }
        ({ config, ... }:
          let
            script = unitScript config "technitium-zone-replication" "technitium-zone-replication";
          in
          {
            assertions = [
              {
                assertion = config.systemd.services ? technitium-zone-replication;
                message = "secondary zones must create the replication unit.";
              }
              {
                assertion =
                  lib.hasInfix "type=Secondary" script
                  && lib.hasInfix "primaryNameServerAddresses=10.10.10.1" script
                  && lib.hasInfix "tsigKeyName=zone-transfer" script;
                message = "the replication script must create a TSIG-authenticated secondary zone.";
              }
              {
                assertion =
                  lib.hasInfix "leaving it unchanged" script
                  && lib.hasInfix "owned-secondaries" script
                  && lib.hasInfix ''if [ "$(zone_type "$zone")" = "Secondary" ]; then'' script;
                message = "the script may delete only owned zones that are still Secondary.";
              }
              {
                assertion = lib.elem "technitium-sync-static-hosts.service" config.systemd.services.technitium-zone-replication.after;
                message = "replication must run after declarative zone creation.";
              }
            ];
          })
      ]);

  router-technitium-zone-replication-shared-tsig-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-shared-tsig"
      (base ++ [
        {
          services.router-technitium = {
            rfc2136 = {
              enable = true;
              tsigKeyFile = "/run/secrets/kea-ddns";
              zones = [ { name = "home.example"; } ];
            };
            zoneReplication = {
              tsigKeyFile = "/run/secrets/zone-transfer";
              primary = {
                zones = [ { name = "home.example"; } ];
                secondaries = [ "10.10.10.4" ];
              };
            };
          };
        }
        ({ config, ... }:
          let
            rfc2136 = unitScript config "technitium-enable-rfc2136" "technitium-enable-rfc2136";
            replication = unitScript config "technitium-zone-replication" "technitium-zone-replication";
            hasBothKeys = script: lib.hasInfix "/run/secrets/kea-ddns" script && lib.hasInfix "/run/secrets/zone-transfer" script;
          in
          {
            assertions = [
              {
                assertion = lib.hasInfix "IFS='|'" rfc2136 && lib.hasInfix "IFS='|'" replication;
                message = "Technitium parses tsigKeys as pipe-separated triples; rows must be joined with |.";
              }
              {
                assertion = hasBothKeys rfc2136 && hasBothKeys replication;
                message = "settings/set replaces the TSIG key list, so each script must register every managed key.";
              }
              {
                assertion =
                  lib.hasInfix "zoneTransfer=UseSpecifiedNetworkACL" replication
                  && lib.hasInfix "zoneTransferNetworkACL=10.10.10.4" replication
                  && lib.hasInfix "notifyNameServers=10.10.10.4" replication;
                message = "primary zones must allow transfers and send NOTIFY only to the listed secondaries.";
              }
            ];
          })
      ]);

  router-technitium-zone-replication-requires-key-fails-eval =
    eval.mkNixosEvalFailureCheck "router-technitium-zone-replication-requires-key"
      (base ++ [
        {
          services.router-technitium.zoneReplication.secondary = {
            zones = [ { name = "home.example"; } ];
            primaryAddresses = [ "10.10.10.1" ];
          };
        }
      ]);

  router-technitium-zone-replication-prune-only-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-prune-only"
      (base ++ [
        ({ config, ... }: {
          assertions = [
            {
              assertion =
                config.systemd.services.technitium-zone-replication.unitConfig.ConditionPathExists
                == "/var/lib/technitium-zone-replication/owned-secondaries";
              message = "with no zones declared the unit must still run when it owns secondaries, to prune them.";
            }
          ];
        })
      ]);
}
