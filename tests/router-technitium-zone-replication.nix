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
                  && lib.hasInfix ''printf '%s\n' home.example >> "$owned_file"'' script
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

  router-technitium-zone-replication-trailing-dot-fails-eval =
    eval.mkNixosEvalFailureCheck "router-technitium-zone-replication-trailing-dot"
      (base ++ [
        {
          services.router-technitium.zoneReplication = {
            tsigKeyFile = "/run/secrets/zone-transfer";
            secondary = {
              zones = [ { name = "home.example."; } ];
              primaryAddresses = [ "10.10.10.1" ];
            };
          };
        }
      ]);

  router-technitium-zone-replication-key-collision-fails-eval =
    eval.mkNixosEvalFailureCheck "router-technitium-zone-replication-key-collision"
      (base ++ [
        {
          services.router-technitium = {
            rfc2136 = {
              enable = true;
              tsigKeyFile = "/run/secrets/kea-ddns";
              zones = [ { name = "home.example"; } ];
            };
            zoneReplication = {
              tsigKeyName = "KEA-DDNS.";
              tsigKeyFile = "/run/secrets/zone-transfer";
              primary = {
                zones = [ { name = "home.example"; } ];
                secondaries = [ "10.10.10.4" ];
              };
            };
          };
        }
      ]);

  # Under zoneReplication.ha the static sync must not create the replicated
  # zone (a Primary on the backup), must skip it while Secondary, and
  # promotion must rerun it. vm-router-technitium-zone-ha covers behaviour.
  router-technitium-zone-replication-ha-static-hosts-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-ha-static-hosts"
      (base ++ [
        self.nixosModules.router-ha
        {
          services.router-ha = {
            enable = true;
            role = "backup";
            virtualIp = "10.10.10.1/16";
            vrrpInterface = "lan0";
            vrrpPasswordFile = "/run/keys/vrrp-password";
          };
          services.router.dnsZones = {
            "home.example".staticHosts.gw.ipAddress = "10.10.10.1";
            "other.example".staticHosts.gw.ipAddress = "10.10.10.1";
          };
          services.router-technitium.zoneReplication = {
            tsigKeyFile = "/run/secrets/zone-transfer";
            secondary = {
              zones = [ { name = "home.example"; } ];
              primaryAddresses = [ "10.10.10.1" ];
            };
            ha = {
              enable = true;
              peers = [ "10.10.10.2" ];
            };
          };
        }
        ({ config, ... }:
          let
            services = config.systemd.services;
            sync = services.technitium-sync-static-hosts.script;
            promote = builtins.readFile services.technitium-zone-ha-owner.serviceConfig.ExecStart;
            demote = builtins.readFile services.technitium-zone-ha-owner.serviceConfig.ExecStop;
            # The sync block of one zone, up to the next zone's block.
            block = zone:
              builtins.head (lib.splitString "Ensuring DNS zone exists:" (
                lib.last (lib.splitString "Ensuring DNS zone exists: ${zone}" (builtins.unsafeDiscardStringContext sync))
              ));
            skipsMissing = zone: lib.hasInfix "= Secondary ] || [ -z \"$type\" ]; then" (block zone);
          in
          {
            assertions = [
              {
                assertion = skipsMissing "home.example" && lib.hasInfix "Skipping home.example" (block "home.example");
                message = "the sync must skip a missing or Secondary HA zone.";
              }
              {
                assertion = !(skipsMissing "other.example") && lib.hasInfix "zones/create" (block "other.example");
                message = "the sync may create a zone outside zoneReplication.ha.";
              }
              {
                assertion = lib.hasInfix "restart technitium-sync-static-hosts.service" promote
                  && !(lib.hasInfix "technitium-sync-static-hosts" demote);
                message = "promotion, not demotion, must rerun the static sync.";
              }
            ];
          })
      ]);

  router-technitium-zone-replication-ha-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-ha"
      (base ++ [
        self.nixosModules.router-ha
        {
          services.router-ha = {
            enable = true;
            role = "backup";
            virtualIp = "10.10.10.1/16";
            vrrpInterface = "lan0";
            vrrpPasswordFile = "/run/keys/vrrp-password";
          };
          services.router-technitium = {
            rfc2136 = {
              enable = true;
              tsigKeyFile = "/run/secrets/kea-ddns";
              zones = [ { name = "home.example"; } ];
            };
            zoneReplication = {
              tsigKeyFile = "/run/secrets/zone-transfer";
              secondary = {
                zones = [ { name = "home.example"; } ];
                primaryAddresses = [ "10.10.10.1" ];
              };
              ha = {
                enable = true;
                peers = [ "10.10.10.2" ];
              };
            };
          };
        }
        ({ config, ... }:
          let
            services = config.systemd.services;
            replication = unitScript config "technitium-zone-replication" "technitium-zone-replication";
            rfc2136 = unitScript config "technitium-enable-rfc2136" "technitium-enable-rfc2136";
            demote = builtins.readFile services.technitium-zone-ha-owner.serviceConfig.ExecStop;
            promote = builtins.readFile services.technitium-zone-ha-owner.serviceConfig.ExecStart;
            before = a: b: text:
              let
                parts = lib.splitString a text;
              in
              builtins.length parts > 1 && lib.hasInfix b (lib.concatStringsSep a (lib.tail parts));
          in
          {
            assertions = [
              {
                assertion = lib.elem "technitium-zone-ha-owner.service" config.services.router-ha.singleActiveUnits;
                message = "the owner unit must be a router-ha single-active unit.";
              }
              {
                assertion = !(services.technitium-zone-ha-owner ? wantedBy) || services.technitium-zone-ha-owner.wantedBy == [ ];
                message = "only router-ha may start the owner unit.";
              }
              {
                assertion = config.systemd.timers ? technitium-zone-ha-reconcile;
                message = "a reconcile timer must retry demotions.";
              }
              {
                assertion = lib.all (lib.hasInfix "flock 9") [ replication promote demote ];
                message = "replication, reconcile and the owner unit must share one lock.";
              }
              {
                assertion = lib.hasInfix "zones/convert" promote && lib.hasInfix "notifyNameServers=10.10.10.2" promote;
                message = "promotion converts to Primary and notifies the peers.";
              }
              {
                assertion =
                  before "if ! primary_answers \"$zone\"" "export_zone \"$zone\" \"$backup\"" demote
                  && before "export_zone \"$zone\" \"$backup\"" "api/zones/delete" demote
                  && lib.hasInfix "has(\"status\")" demote;
                message = "demotion must check a primary answers, then export, then delete.";
              }
              {
                assertion =
                  lib.hasInfix "this node is VRRP MASTER" demote
                  && lib.hasInfix "is_local_address \"$addr\"" demote
                  && lib.hasInfix "export failed or returned no zone data" demote;
                message = "demotion refuses on MASTER, ignores its own VIP, and aborts on a bad export.";
              }
              {
                # Bounded retries, with the local-address check inside the loop.
                assertion = before "for _try in 1 2 3; do" "is_local_address \"$addr\"" demote;
                message = "the SOA check retries three times and re-checks the VIP on every attempt.";
              }
              {
                assertion = lib.hasInfix "! is_master; then" replication && lib.hasInfix "demote_zone home.example" replication;
                message = "the replication run must demote a Primary on a node that is not MASTER.";
              }
              {
                # The MASTER sends NOTIFY from its own address, not the VIP.
                # GOTCHA: check the per-run update of an existing Secondary (the
                # call after "Updating secondary zone"), not only the create.
                assertion =
                  before "Updating secondary zone" "primaryNameServerAddresses=10.10.10.1,10.10.10.2" replication
                  && lib.hasInfix "primaryNameServerAddresses=10.10.10.1,10.10.10.2" demote;
                message = "under ha a Secondary must list the peers after the VIP so it accepts their NOTIFY.";
              }
              {
                assertion = lib.hasInfix "not Primary on this node" rfc2136;
                message = "RFC2136 settings skip zones this node does not hold as Primary.";
              }
            ];
          })
      ]);

  router-technitium-zone-replication-ha-needs-peers-fails-eval =
    eval.mkNixosEvalFailureCheck "router-technitium-zone-replication-ha-needs-peers"
      (base ++ [
        {
          services.router-technitium.zoneReplication = {
            tsigKeyFile = "/run/secrets/zone-transfer";
            secondary = {
              zones = [ { name = "home.example"; } ];
              primaryAddresses = [ "10.10.10.1" ];
            };
            ha.enable = true;
          };
        }
      ]);

  # Removing the last HA zone must still evaluate, so cleanup can run.
  router-technitium-zone-replication-ha-empty-eval =
    eval.mkNixosEvalCheck "router-technitium-zone-replication-ha-empty"
      (base ++ [
        {
          services.router-technitium.zoneReplication = {
            tsigKeyFile = "/run/secrets/zone-transfer";
            ha.enable = true;
          };
        }
        ({ config, ... }: {
          assertions = [
            {
              assertion = config.systemd.services ? technitium-zone-replication;
              message = "the replication unit stays installed to prune the last HA zone.";
            }
          ];
        })
      ]);
}
