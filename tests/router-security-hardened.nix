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
          blockedCountries = [
            "ru"
            "cn"
          ];
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
          assertion = builtins.elem "multi-user.target" config.systemd.services.update-geoip-blocklist.wantedBy;
          message = "router-security-hardened should trigger an initial Geo-IP population on boot.";
        }
        {
          assertion = lib.hasInfix ''nft -f "$tmp_commands"'' config.systemd.services.update-geoip-blocklist.script;
          message = "router-security-hardened should batch Geo-IP nft updates.";
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
          assertion = lib.hasInfix ''set allowed_macs_br_lan'' config.networking.nftables.ruleset;
          message = "router-security-hardened should sanitize MAC set names for common interface names.";
        }
        {
          assertion = lib.hasInfix ''log prefix "MAC-ALERT: " return'' config.networking.nftables.ruleset;
          message = "router-security-hardened alert mode should log and continue normal forward evaluation.";
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
          assertion = lib.hasInfix ''@allowed_macs_br_lan'' config.networking.nftables.ruleset;
          message = "router-security-hardened should reference the sanitized MAC set name.";
        }
        {
          assertion = lib.hasInfix ''log prefix "MAC-REJECT: " drop'' config.networking.nftables.ruleset;
          message = "router-security-hardened enforce mode should log and drop.";
        }
      ];
    })
  ];

  router-security-hardened-egress-bogon-eval = eval.mkNixosEvalCheck "router-security-hardened-egress-bogon" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        egressBogonBlocking.enable = true;
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = lib.hasInfix ''set wan_egress_bogon_ipv4'' config.networking.nftables.ruleset;
          message = "router-security-hardened should declare the WAN egress bogon set when enabled.";
        }
        {
          assertion = lib.hasInfix ''elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10'' config.networking.nftables.ruleset;
          message = "router-security-hardened should populate the default WAN egress bogon IPv4 ranges.";
        }
        {
          assertion = lib.hasInfix ''jump egress_bogon_block'' config.networking.nftables.ruleset;
          message = "router-security-hardened should insert the WAN egress bogon jump into nftables evaluation.";
        }
        {
          assertion = lib.hasInfix ''oifname {"eth0"} ip daddr @wan_egress_bogon_ipv4 drop comment "router-security-hardened WAN egress bogon block"'' config.networking.nftables.ruleset;
          message = "router-security-hardened should scope WAN egress bogon blocking to WAN-bound traffic.";
        }
      ];
    })
  ];

  router-security-hardened-egress-bogon-disabled-eval = eval.mkNixosEvalCheck "router-security-hardened-egress-bogon-disabled" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened.enable = true;
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = !(lib.hasInfix ''wan_egress_bogon_ipv4'' config.networking.nftables.ruleset);
          message = "router-security-hardened should not render WAN egress bogon rules when disabled.";
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

  router-security-hardened-egress-bogon-empty-fails = eval.mkNixosEvalFailureCheck "router-security-hardened-egress-bogon-empty" [
    self.nixosModules.router-firewall
    self.nixosModules.router-security-hardened
    {
      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "eth0" ];
      };

      services.router-security-hardened = {
        enable = true;
        egressBogonBlocking = {
          enable = true;
          ipv4Cidrs = [ ];
        };
      };
    }
  ];
}
