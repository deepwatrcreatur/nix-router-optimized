{
  self,
  lib,
  eval,
}:

let
  assertModule = assertions: { inherit assertions; };
  extractNotifyScript =
    key: extraConfig:
    let
      line = builtins.head (builtins.filter (lib.hasPrefix "${key} \"") (lib.splitString "\n" extraConfig));
      trimmed = lib.removePrefix "${key} \"" line;
    in
    lib.removeSuffix "\"" trimmed;
in
{
  router-ndppd-basic-eval = eval.mkNixosEvalCheck "router-ndppd-basic" [
    self.nixosModules.router-ndp-proxy
    {
      services.router-ndp-proxy = {
        enable = true;
        upstreamInterface = "eth-wan";
        downstreamInterfaces = [ "br-lan" ];
        prefixes = [
          {
            prefix = "2001:db8:100::/64";
            method = "interface";
            downstreamInterface = "br-lan";
          }
          {
            prefix = "2001:db8:101::/64";
            method = "auto";
          }
        ];
      };
    }
    ({ config, ... }:
      let
        ndppdConf = config.environment.etc."ndppd.conf".text;
        ndppdService = config.systemd.services.router-ndp-proxy;
      in
      assertModule [
        {
          assertion = lib.hasInfix "proxy eth-wan" ndppdConf;
          message = "router-ndp-proxy should render the upstream proxy interface.";
        }
        {
          assertion = lib.hasInfix "rule 2001:db8:100::/64" ndppdConf && lib.hasInfix "iface br-lan" ndppdConf;
          message = "router-ndp-proxy should render interface-based prefix rules deterministically.";
        }
        {
          assertion = lib.hasInfix "rule 2001:db8:101::/64" ndppdConf && lib.hasInfix "auto" ndppdConf;
          message = "router-ndp-proxy should render auto-mode prefix rules deterministically.";
        }
        {
          assertion = lib.hasInfix "/bin/ndppd" ndppdService.serviceConfig.ExecStart;
          message = "router-ndp-proxy should run the packaged ndppd binary.";
        }
        {
          assertion = builtins.elem "multi-user.target" ndppdService.wantedBy;
          message = "router-ndp-proxy should auto-start outside HA single-active-owner mode.";
        }
      ])
  ];

  router-ndppd-ha-blocked-eval = eval.mkNixosEvalFailureCheck "router-ndppd-ha-blocked" [
    self.nixosModules.router-ha
    self.nixosModules.router-ndp-proxy
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "2001:db8::1/64";
        vrrpInterface = "lan0";
      };

      services.router-ndp-proxy = {
        enable = true;
        upstreamInterface = "eth-wan";
        downstreamInterfaces = [ "br-lan" ];
        prefixes = [
          {
            prefix = "2001:db8:100::/64";
            method = "interface";
            downstreamInterface = "br-lan";
          }
        ];
      };
    }
  ];

  router-ndppd-single-active-without-ha-fails = eval.mkNixosEvalFailureCheck "router-ndppd-single-active-without-ha" [
    self.nixosModules.router-ha
    self.nixosModules.router-ndp-proxy
    {
      services.router-ndp-proxy = {
        enable = true;
        upstreamInterface = "eth-wan";
        downstreamInterfaces = [ "br-lan" ];
        ha.singleActiveOwner = true;
        prefixes = [
          {
            prefix = "2001:db8:100::/64";
            method = "interface";
            downstreamInterface = "br-lan";
          }
        ];
      };
    }
  ];

  router-ndppd-ha-single-active-owner-eval = eval.mkNixosEvalCheck "router-ndppd-ha-single-active-owner" [
    self.nixosModules.router-ha
    self.nixosModules.router-ndp-proxy
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "2001:db8::1/64";
        vrrpInterface = "lan0";
      };

      services.router-ndp-proxy = {
        enable = true;
        upstreamInterface = "eth-wan";
        downstreamInterfaces = [ "br-lan" ];
        ha.singleActiveOwner = true;
        prefixes = [
          {
            prefix = "2001:db8:100::/64";
            method = "interface";
            downstreamInterface = "br-lan";
          }
        ];
      };
    }
    ({ config, ... }:
      let
        keepalivedConfig = config.services.keepalived.vrrpInstances.main.extraConfig;
        masterScript = extractNotifyScript "notify_master" keepalivedConfig;
        backupScript = extractNotifyScript "notify_backup" keepalivedConfig;
        faultScript = extractNotifyScript "notify_fault" keepalivedConfig;
        ndppdService = config.systemd.services.router-ndp-proxy;
      in
      assertModule [
        {
          assertion = ndppdService.wantedBy == [ ];
          message = "router-ndp-proxy should not auto-start when singleActiveOwner is enabled.";
        }
        {
          assertion = lib.hasInfix "systemctl start router-ndp-proxy.service" (builtins.readFile masterScript);
          message = "router-ha should start router-ndp-proxy on master promotion.";
        }
        {
          assertion =
            lib.hasInfix "systemctl stop router-ndp-proxy.service" (builtins.readFile backupScript)
            && lib.hasInfix "systemctl stop router-ndp-proxy.service" (builtins.readFile faultScript);
          message = "router-ha should stop router-ndp-proxy on backup and fault transitions.";
        }
      ])
  ];
}
