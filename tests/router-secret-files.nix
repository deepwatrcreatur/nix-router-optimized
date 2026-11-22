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
              && config.systemd.services.technitium-dns-server.environment.DNS_SERVER_ADMIN_PASSWORD_FILE == adminPassword;
            message = "router-technitium.bootstrapPasswordFile must enable the token bootstrap and set DNS_SERVER_ADMIN_PASSWORD_FILE.";
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
}
