{
  self,
  lib,
  eval,
  ...
}:

{
  router-security-hardened-kernel-eval = eval.mkNixosEvalCheck "router-security-hardened-kernel" [
    self.nixosModules.router-security-hardened
    {
      services.router-security-hardened = {
        enable = true;
        kernelHardening = {
          enable = true;
          allowPing = false;
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.boot.kernel.sysctl."kernel.kptr_restrict" == 2;
          message = "router-security-hardened should set kptr_restrict.";
        }
        {
          assertion = config.boot.kernel.sysctl."net.ipv4.icmp_echo_ignore_all" == 1;
          message = "router-security-hardened should disable ping when allowPing is false.";
        }
        {
          assertion = builtins.elem "bluetooth" config.boot.blacklistedKernelModules;
          message = "router-security-hardened should blacklist bluetooth.";
        }
      ];
    })
  ];

  router-security-hardened-geoip-eval = eval.mkNixosEvalCheck "router-security-hardened-geoip" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        geoIpBlocking = {
          enable = true;
          blockedCountries = [ "ru" "cn" ];
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''jump geoip_block'' config.networking.nftables.ruleset;
          message = "router-security-hardened should insert the Geo-IP jump in input.";
        }
        {
          assertion = lib.hasInfix ''iifname {"eth0"} ip saddr @blocked_countries drop'' config.networking.nftables.ruleset;
          message = "router-security-hardened should scope Geo-IP blocking to WAN ingress.";
        }
        {
          assertion = lib.hasInfix ''https://www.ipdeny.com/ipblocks/data/countries/'' config.systemd.services.update-geoip-blocklist.script;
          message = "router-security-hardened should fetch Geo-IP data over HTTPS.";
        }
      ];
    })
  ];

  router-security-hardened-mac-alert-eval = eval.mkNixosEvalCheck "router-security-hardened-mac-alert" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        macSecurity = {
          enable = true;
          policy = "alert";
          whitelists.br-lan = [ "00:11:22:33:44:55" ];
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''elements = { 00:11:22:33:44:55 }'' config.networking.nftables.ruleset;
          message = "router-security-hardened should materialize the MAC allowlist set.";
        }
        {
          assertion = lib.hasInfix ''log prefix "MAC-ALERT: " accept'' config.networking.nftables.ruleset;
          message = "router-security-hardened alert mode should log and allow.";
        }
      ];
    })
  ];

  router-security-hardened-mac-enforce-eval = eval.mkNixosEvalCheck "router-security-hardened-mac-enforce" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        macSecurity = {
          enable = true;
          policy = "enforce";
          whitelists.br-lan = [ "00:11:22:33:44:55" ];
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''jump mac_security'' config.networking.nftables.ruleset;
          message = "router-security-hardened should insert the MAC chain early in forward.";
        }
        {
          assertion = lib.hasInfix ''log prefix "MAC-REJECT: " drop'' config.networking.nftables.ruleset;
          message = "router-security-hardened enforce mode should log and drop.";
        }
      ];
    })
  ];

  router-security-hardened-geoip-empty-fails = eval.mkNixosEvalFailureCheck "router-security-hardened-geoip-empty" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        geoIpBlocking.enable = true;
      };
    }
  ];

  router-security-hardened-mac-empty-fails = eval.mkNixosEvalFailureCheck "router-security-hardened-mac-empty" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        macSecurity = {
          enable = true;
          whitelists = { };
        };
      };
    }
  ];
}
