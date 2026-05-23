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
in
{
  router-dhcp-option108-unsupported-fails-eval = eval.mkNixosEvalFailureCheck "router-dhcp-option108-unsupported" [
    self.nixosModules.router-networking
    self.nixosModules.router-dhcp
    {
      services.router-networking = {
        enable = true;
        wan.device = "ens17";
        routedInterfaces.lan = {
          device = "ens16";
          ipv4Address = "192.168.1.1/24";
          dns = [ "192.168.1.1" ];
        };
      };

      services.router-dhcp = {
        enable = true;
        interfaces.lan.option108.enable = true;
      };
    }
  ];

  router-technitium-option108-unsupported-fails-eval = eval.mkNixosEvalFailureCheck "router-technitium-option108-unsupported" [
    ageSecretStub
    self.nixosModules.router-technitium
    {
      age.secrets.technitium-api-key.path = "/run/agenix/technitium-api-key";

      services.router-technitium = {
        enable = true;
        scopes.LAN = {
          startingAddress = "10.10.10.100";
          endingAddress = "10.10.10.150";
          subnetMask = "255.255.255.0";
          routerAddress = "10.10.10.1";
          option108.enable = true;
        };
      };
    }
  ];
}
