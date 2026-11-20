{
  self,
  lib,
  pkgs,
  nixpkgs,
  system,
  eval,
}:

let
  haBase = extra: {
    services.router-ha = {
      enable = true;
      role = "master";
      virtualIp = "10.10.10.1/24";
      vrrpInterface = "lan0";
    } // extra;
  };

  fileConfig =
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        {
          networking.hostName = "router-check";
          system.stateVersion = "25.11";
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.devices = [ "nodev" ];
        }
        self.nixosModules.router-ha
        (haBase { vrrpPasswordFile = "/run/keys/vrrp-password"; })
      ];
    }).config;

  realScript = fileConfig.systemd.services.router-ha-vrrp-secret.script;

  # The unit writes to /run/router-ha; point its one `dir=` line at a scratch
  # directory so the real script can run inside the build sandbox.
  dirLine = "dir=${lib.escapeShellArg "/run/router-ha"}";
  secretScript =
    assert lib.hasInfix dirLine realScript;
    pkgs.writeShellScript "router-ha-vrrp-secret-test" (
      lib.replaceStrings [ dirLine ] [ "dir=\"$RUNTIME_DIR\"" ] realScript
    );
in
{
  router-ha-vrrp-password-file-eval = eval.mkNixosEvalCheck "router-ha-vrrp-password-file" [
    self.nixosModules.router-ha
    (haBase { vrrpPasswordFile = "/run/keys/vrrp-password"; })
    ({ config, ... }:
      let
        conf = config.services.keepalived.vrrpInstances.main.extraConfig;
        unit = config.systemd.services.router-ha-vrrp-secret;
      in
      {
        assertions = [
          {
            assertion = lib.hasInfix "auth_pass $ROUTER_HA_VRRP_PASS" conf;
            message = "keepalived.conf must reference the runtime variable, not a literal password.";
          }
          {
            assertion = config.services.keepalived.secretFile == "/run/router-ha/vrrp-secret.env";
            message = "keepalived must envsubst the rendered secret file.";
          }
          {
            assertion = unit.serviceConfig.LoadCredential == [ "vrrp-password:/run/keys/vrrp-password" ];
            message = "the password file must be loaded as a systemd credential.";
          }
          {
            assertion =
              lib.elem "keepalived.service" unit.requiredBy
              && lib.elem "keepalived.service" unit.partOf
              && lib.elem "router-ha-vrrp-secret.service" config.systemd.services.keepalived.after;
            message = "the secret must be rendered before every keepalived start.";
          }
          {
            assertion = config.warnings == [ ];
            message = "vrrpPasswordFile must not trigger the deprecation warning.";
          }
        ];
      })
  ];

  router-ha-vrrp-inline-password-eval = eval.mkNixosEvalCheck "router-ha-vrrp-inline-password" [
    self.nixosModules.router-ha
    (haBase { vrrpPassword = "legacy"; })
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix "auth_pass legacy" config.services.keepalived.vrrpInstances.main.extraConfig;
          message = "the deprecated inline password must still render.";
        }
        {
          assertion = lib.any (lib.hasInfix "vrrpPasswordFile") config.warnings;
          message = "the inline password must warn about the Nix store.";
        }
        {
          assertion = !(config.systemd.services ? router-ha-vrrp-secret);
          message = "no secret unit without vrrpPasswordFile.";
        }
      ];
    })
  ];

  router-ha-vrrp-no-password-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-vrrp-no-password" [
    self.nixosModules.router-ha
    (haBase { })
  ];

  router-ha-vrrp-both-passwords-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-vrrp-both-passwords" [
    self.nixosModules.router-ha
    (haBase {
      vrrpPassword = "legacy";
      vrrpPasswordFile = "/run/keys/vrrp-password";
    })
  ];

  router-ha-vrrp-bad-inline-password-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-vrrp-bad-inline-password" [
    self.nixosModules.router-ha
    (haBase { vrrpPassword = "a b"; })
  ];

  router-ha-vrrp-secret-runtime =
    pkgs.runCommand "router-ha-vrrp-secret-runtime"
      {
        nativeBuildInputs = [ pkgs.shellcheck ];
      }
      ''
        set -euo pipefail
        shellcheck -s bash ${pkgs.writeText "router-ha-vrrp-secret.sh" realScript}

        run() {
          export CREDENTIALS_DIRECTORY=$PWD/creds RUNTIME_DIR=$PWD/run
          rm -rf creds run
          mkdir creds
          printf '%s' "$1" > creds/vrrp-password
          ${secretScript} 2> err
        }

        run 'S3cret!x' && { echo "accepted a password containing !" >&2; exit 1; }
        run 'with space' && { echo "accepted a password with whitespace" >&2; exit 1; }
        run "" && { echo "accepted an empty password" >&2; exit 1; }

        run $'abc123\r\nignored'
        [ "$(cat run/vrrp-secret.env)" = "ROUTER_HA_VRRP_PASS=abc123" ] || { cat run/vrrp-secret.env; exit 1; }
        [ "$(stat -c %a run/vrrp-secret.env)" = 600 ]
        [ ! -s err ]

        run 'longer-than-8'
        grep -q 'first 8 characters' err

        touch "$out"
      '';
}
