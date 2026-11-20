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
  keepalivedPreStart = builtins.head fileConfig.systemd.services.keepalived.serviceConfig.ExecStartPre;

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
            assertion = lib.hasInfix "auth_pass \"$ROUTER_HA_VRRP_PASS\"" conf;
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
          assertion = lib.hasInfix "auth_pass \"legacy\"" config.services.keepalived.vrrpInstances.main.extraConfig;
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

  router-ha-vrrp-store-password-file-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-vrrp-store-password-file" [
    self.nixosModules.router-ha
    (haBase { vrrpPasswordFile = "${builtins.storeDir}/00000000000000000000000000000000-vrrp-password"; })
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

        run 'bad!char' && { echo "accepted a password containing !" >&2; exit 1; }
        run 'with space' && { echo "accepted a password with whitespace" >&2; exit 1; }
        run "" && { echo "accepted an empty password" >&2; exit 1; }

        value=labonly1
        run "$value"$'\r\nignored'
        expected="ROUTER_HA_VRRP_PASS"="$value"
        [ "$(cat run/vrrp-secret.env)" = "$expected" ] || { cat run/vrrp-secret.env; exit 1; }
        [ "$(stat -c %a run/vrrp-secret.env)" = 600 ]
        [ ! -s err ]

        run 'longer-than-8'
        grep -q 'first 8 characters' err

        # Render the final config the way the upstream ExecStartPre does and
        # let keepalived parse it. Braces must stay inside the quoted value.
        # GOTCHA: the sandbox has no lan0, so only interface messages are ok.
        conf=$(grep -o '/nix/store/[^" ]*keepalived.conf' ${keepalivedPreStart} | head -n1)
        for value in '{lab1' 'la}b{2' 'plain3'; do
          run "$value"
          set -a; . run/vrrp-secret.env; set +a
          ${pkgs.envsubst}/bin/envsubst -i "$conf" > final.conf
          grep -qF "auth_pass \"$value\"" final.conf || { grep auth_pass final.conf; exit 1; }
          rm -f test.log
          ${pkgs.keepalived}/bin/keepalived --config-test="$PWD/test.log" -f "$PWD/final.conf" -l 2> kstderr || true
          if cat test.log kstderr | grep -vE "interface lan0 for vrrp_instance main doesn't exist|Non-existent interface specified" | grep -q .; then
            echo "keepalived rejected a config rendered from '$value':" >&2
            cat test.log kstderr >&2
            exit 1
          fi
        done

        touch "$out"
      '';
}
