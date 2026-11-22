{
  self,
  lib,
  eval,
}:

let
  apiKey = "/run/secrets/technitium-api-key";
  adminPassword = "/run/secrets/technitium-admin-password";
  cloudflareToken = "/run/secrets/cloudflare-api-token";
  warpLicense = "/run/secrets/warp-license-key";
in
{
  # Credentials passed as *File paths must work with no agenix module
  # imported at all (clan vars / sops-nix consumers), and must reach every
  # module that used to look them up through config.age.secrets.
  router-secret-file-options-without-agenix-eval = eval.mkNixosEvalCheck "router-secret-file-options-without-agenix" [
    self.nixosModules.router-technitium
    self.nixosModules.router-dashboard
    self.nixosModules.router-cloudflare-warp
    {
      services.router-technitium = {
        enable = true;
        apiKeyFile = apiKey;
        bootstrapPasswordFile = adminPassword;
      };
      services.router-dashboard = {
        enable = true;
        cloudflareTokenFile = cloudflareToken;
      };
      services.router-cloudflare-warp = {
        enable = true;
        licenseKeyFile = warpLicense;
      };
    }
    ({ config, options, ... }:
      let
        dashEnv = config.systemd.services.router-dashboard.environment;
        warpScript = config.systemd.services.router-cloudflare-warp-setup.script;
      in
      {
        assertions = [
          {
            assertion = !(options ? age);
            message = "This check must evaluate without the agenix module.";
          }
          {
            assertion = config.services.router-technitium.resolvedApiKeyFile == apiKey
              && config.environment.variables.TECHNITIUM_API_KEY_FILE == apiKey;
            message = "router-technitium.apiKeyFile must be exported as TECHNITIUM_API_KEY_FILE and resolvedApiKeyFile.";
          }
          {
            assertion = config.systemd.services ? technitium-bootstrap-api-token
              && config.systemd.services.technitium-dns-server.environment.DNS_SERVER_ADMIN_PASSWORD_FILE == "%d/admin-password"
              && builtins.elem "admin-password:${adminPassword}" config.systemd.services.technitium-dns-server.serviceConfig.LoadCredential;
            message = "router-technitium.bootstrapPasswordFile must enable the token bootstrap and reach Technitium through LoadCredential (it runs as a DynamicUser that cannot read root-only files).";
          }
          {
            assertion = dashEnv.TECHNITIUM_API_KEY_FILE == apiKey
              && dashEnv.DASHBOARD_CLOUDFLARE_TOKEN_FILE == cloudflareToken;
            message = "router-dashboard must take the Technitium token from resolvedApiKeyFile and the Cloudflare token from cloudflareTokenFile.";
          }
          {
            assertion = lib.hasInfix warpLicense warpScript;
            message = "router-cloudflare-warp.licenseKeyFile must be read by router-cloudflare-warp-setup.";
          }
        ];
      })
  ];

  # Without router-technitium, router-dashboard must still find the historical
  # technitium-api-key age secret.
  router-dashboard-standalone-age-token-fallback-eval = eval.mkNixosEvalCheck "router-dashboard-standalone-age-token-fallback" [
    self.nixosModules.router-dashboard
    ({ lib, ... }: {
      # Minimal stand-in for the agenix module's option.
      options.age.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule { options.path = lib.mkOption { type = lib.types.str; }; });
        default = { };
      };
      config = {
        age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";
        services.router-dashboard.enable = true;
      };
    })
    ({ config, ... }: {
      assertions = [
        {
          assertion = !(config.services ? router-technitium)
            && config.systemd.services.router-dashboard.environment.TECHNITIUM_API_KEY_FILE == "/run/agenix/technitium-api-key";
          message = "A standalone router-dashboard must fall back to age.secrets.technitium-api-key.";
        }
      ];
    })
  ];
}
