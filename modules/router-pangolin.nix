{
  config,
  lib,
  pkgs,
  options,
  utils,
  ...
}:

with lib;

let
  cfg = config.services.router-pangolin;
  hasRouterOption = path: hasAttrByPath path options;
  # WHY: gerbil < 1.5.2 closes its relay packet channel twice on shutdown
  # (fosrl/gerbil#51), so every stop panics with exit 2 and the unit is
  # marked failed; on a VRRP pair that is every demotion. Prefer nixpkgs'
  # package once it carries the fix.
  # UPSTREAM: drop the local build when the pinned nixpkgs has >= 1.5.2.
  defaultGerbil =
    if versionAtLeast pkgs.fosrl-gerbil.version "1.5.2" then
      pkgs.fosrl-gerbil
    else
      # WHY: 1.5.2 (not 1.6.0) because 1.6.0 needs Go 1.26.9; 1.5.2 builds
      # with any Go 1.26.
      pkgs.buildGo126Module (finalAttrs: {
        pname = "gerbil";
        version = "1.5.2";
        src = pkgs.fetchFromGitHub {
          owner = "fosrl";
          repo = "gerbil";
          tag = finalAttrs.version;
          hash = "sha256-vxmmu5Atad5nQwZQ1xySKPrTzO0z12PBxKtfRhkygFI=";
        };
        vendorHash = "sha256-aEP2aYBZB0XKfJoFBxLtUUCdPqmGLNz7SE+89tnaIms=";
        postPatch = ''
          substituteInPlace main.go \
            --replace-fail '/usr/sbin/iptables' '${getExe pkgs.iptables}'
        '';
        meta = pkgs.fosrl-gerbil.meta // { mainProgram = "gerbil"; };
      });
  firewallEnabled =
    if hasRouterOption [ "services" "router-firewall" "enable" ] then
      (config.services.router-firewall.enable or false)
    else
      false;
in
{
  options.services.router-pangolin = {
    enable = mkEnableOption "router-aware Pangolin tunnel/reverse proxy integration";

    baseDomain = mkOption {
      type = types.nullOr types.str;
      default = "deepwatercreature.com";
      description = "Base domain for Pangolin tunnel endpoints.";
    };

    dashboardDomain = mkOption {
      type = types.nullOr types.str;
      default = "pangolin.deepwatercreature.com";
      description = "Dashboard domain for Pangolin management interface.";
    };

    letsEncryptEmail = mkOption {
      type = types.nullOr types.str;
      default = "deepwatrcreatur@gmail.com";
      description = "Email for ACME Let's Encrypt certificates.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = "/etc/pangolin/pangolin.env";
      description = "Path to environment file containing secrets for Pangolin.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically open required ports in router-firewall / system firewall.";
    };

    gerbilPackage = mkOption {
      type = types.package;
      default = defaultGerbil;
      defaultText = literalExpression "pkgs.fosrl-gerbil if >= 1.5.2, else gerbil 1.5.2";
      description = ''
        Gerbil package for the `gerbil` unit. The nixpkgs Pangolin module
        hard-codes `pkgs.fosrl-gerbil`; releases before 1.5.2 panic on every
        stop ("close of closed channel"), which marks the unit failed.
      '';
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Additional configuration settings for Pangolin.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.pangolin = {
        enable = true;
        openFirewall = cfg.openFirewall;
        settings = recursiveUpdate {
          server = {
            # Default internal_port 3001 conflicts with Grafana (http_port = 3001)
            internal_port = 3005;
            # GOTCHA: Pangolin 1.24 added an AI gateway listener whose default
            # port is 3005, so it collided with internal_port and Pangolin
            # exited with EADDRINUSE. Older releases ignore the key.
            ai_gateway_port = 3006;
          };
        } cfg.settings;
      }
      // optionalAttrs (cfg.baseDomain != null) { baseDomain = cfg.baseDomain; }
      // optionalAttrs (cfg.dashboardDomain != null) { dashboardDomain = cfg.dashboardDomain; }
      // optionalAttrs (cfg.letsEncryptEmail != null) { letsEncryptEmail = cfg.letsEncryptEmail; }
      // optionalAttrs (cfg.environmentFile != null) { environmentFile = cfg.environmentFile; };

      # INVARIANT: same arguments as the nixpkgs module's ExecStart, which
      # names pkgs.fosrl-gerbil directly and has no package option.
      systemd.services.gerbil.serviceConfig.ExecStart = mkForce (
        utils.escapeSystemdExecArgs [
          (getExe cfg.gerbilPackage)
          "--reachableAt=http://localhost:${toString config.services.gerbil.port}"
          "--generateAndSaveKeyTo=${toString config.services.pangolin.dataDir}/config/key"
          "--remoteConfig=http://localhost:${toString config.services.pangolin.settings.server.internal_port}/api/v1/gerbil/get-config"
        ]
      );

      # GOTCHA: upstream runs pangolin as `pangolin` with ProtectSystem=full,
      # so /etc is read-only to it and preStart cannot create /etc/pangolin on
      # a fresh host (docs/router-pangolin.md).
      systemd.services.pangolin = {
        serviceConfig = {
          # "+" runs outside the sandbox as root. Creating the directory on
          # every start (not via tmpfiles) also covers it being deleted while
          # the system runs; an existing directory keeps its mode.
          ExecStartPre = lib.mkBefore [
            "+${pkgs.writeShellScript "pangolin-etc-dir" ''
              [ -d /etc/pangolin ] || ${pkgs.coreutils}/bin/install -d -m 0750 -o pangolin -g fossorial /etc/pangolin
            ''}"
          ];
          # "-": a missing path must not abort sandbox setup before the step
          # above has created it.
          ReadWritePaths = [ "-/etc/pangolin" ];
          # Loosen SocketBindDeny so Node process can bind listening TCP ports on localhost
          SocketBindDeny = lib.mkForce [
            "ipv4:udp"
            "ipv6:udp"
          ];
        } // optionalAttrs (cfg.environmentFile != null) {
          EnvironmentFile = lib.mkForce [ "-${cfg.environmentFile}" ];
        };

        preStart = lib.mkBefore ''
          # Ensure secret file exists. umask 077 so it is never group- or
          # world-readable, not even before the chmod.
          if [ ! -f /etc/pangolin/pangolin.env ]; then
            (umask 077; echo "SERVER_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)" > /etc/pangolin/pangolin.env)
            chmod 600 /etc/pangolin/pangolin.env
            chown pangolin:fossorial /etc/pangolin/pangolin.env 2>/dev/null || true
          fi

          # Fix read-only permissions on .next directory from Nix store cp -rd and ensure skip setup marker
          if [ -d /var/lib/pangolin/.next ]; then
            chmod -R u+rwX /var/lib/pangolin/.next 2>/dev/null || true
            touch /var/lib/pangolin/.next/.nix_skip_setup 2>/dev/null || true
          fi

          # Ensure database JSON references in server/db are linked from dist
          mkdir -p /var/lib/pangolin/server/db
          for json in ${config.services.pangolin.package}/share/pangolin/dist/*.json; do
            if [ -f "$json" ]; then
              ln -sf "$json" /var/lib/pangolin/server/db/$(basename "$json")
            fi
          done
          chown -R pangolin:fossorial /var/lib/pangolin/server 2>/dev/null || true
        '';
      };
    }
    (optionalAttrs (hasRouterOption [ "services" "router-firewall" "enable" ]) {
      services.router-firewall = mkIf (firewallEnabled && cfg.openFirewall) {
        wanTcpPorts = [ 80 443 ];
        trustedTcpPorts = [ 3000 3002 ];
      };
    })
  ]);
}
