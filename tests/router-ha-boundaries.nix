{
  self,
  lib,
  pkgs,
  nixpkgs,
  system,
  eval,
}:

let
  garpSystem =
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
        {
          services.router-ha = {
            enable = true;
            role = "master";
            virtualIp = "10.10.10.1/16";
            vrrpInterface = "eth9";
            vrrpPasswordFile = "/run/keys/vrrp-password";
            preemptDelay = 60;
            garp = {
              masterDelay = 0;
              masterRepeat = 3;
              lowerPrioDelay = 2;
              lowerPrioRepeat = 2;
              masterRefresh = 60;
              masterRefreshRepeat = 2;
            };
          };
        }
      ];
    }).config;
  # WHY: with vrrpPasswordFile, ExecStart reads the rendered /run copy; the
  # store keepalived.conf (password still a $VAR) is named in ExecStartPre.
  keepalivedPreStart = builtins.head garpSystem.systemd.services.keepalived.serviceConfig.ExecStartPre;
  keaHaPair = extraHa: [
    self.nixosModules.router-ha
    self.nixosModules.router-kea
    self.nixosModules.router-firewall
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "lan0";
        vrrpPasswordFile = "/run/keys/vrrp-password";
      } // extraHa;

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "wan0" ];
        lanInterfaces = [ "lan0" ];
      };

      services.router-kea = {
        enable = true;
        dhcp4 = {
          interfaces = [ "lan0" ];
          subnet = "10.10.10.0/24";
          gatewayAddress = "10.10.10.1";
          poolRanges = [
            {
              start = "10.10.10.100";
              end = "10.10.10.199";
            }
          ];
          ha = {
            enable = true;
            thisServerName = "router-a";
            peerName = "router-b";
            role = "primary";
            localAddress = "10.10.10.2";
            peerAddress = "10.10.10.3";
          };
        };
      };
    }
  ];
in
{
  router-ha-kea-ha-eval = eval.mkNixosEvalCheck "router-ha-kea-ha" (
    keaHaPair { keaSync.enable = true; }
    ++ [
      ({ config, ... }:
        let
          inputRules = config.services.router-firewall.extraInputRules;
          haHook = lib.findFirst (h: h ? parameters) null config.services.kea.dhcp4.settings.hooks-libraries;
          peers = (builtins.head haHook.parameters.high-availability).peers;
        in
        {
          assertions = [
            {
              assertion = lib.hasInfix "ip saddr 10.10.10.3 tcp dport 8000 accept" inputRules;
              message = "the Kea HA port must be open to the peer address.";
            }
            {
              assertion =
                !(lib.elem 8000 config.services.router-firewall.trustedTcpPorts)
                && !(lib.hasInfix "Allow Kea HA sync" inputRules);
              message = "the Kea HA port must not be open to every client or interface.";
            }
            {
              assertion = map (p: p.url) peers == [ "http://10.10.10.2:8000/" "http://10.10.10.3:8000/" ];
              message = "Kea HA peer URLs must use the configured addresses.";
            }
            {
              assertion =
                let
                  ha = builtins.head haHook.parameters.high-availability;
                in
                ha.heartbeat-delay == 5000 && ha.max-response-delay == 15000 && ha.max-unacked-clients == 0;
              message = "Kea HA must default to a 5 s heartbeat and 15 s takeover.";
            }
            {
              assertion = lib.any (lib.hasInfix "keaSync is deprecated") config.warnings;
              message = "keaSync must warn that it is deprecated.";
            }
          ];
        })
    ]
  );

  router-kea-ha-timing-fails-eval = eval.mkNixosEvalFailureCheck "router-kea-ha-timing" (
    keaHaPair { }
    ++ [
      {
        services.router-kea.dhcp4.ha = {
          heartbeatDelaySec = 20;
          maxResponseDelaySec = 15;
        };
      }
    ]
  );

  router-ha-kea-ha-single-active-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-kea-ha-single-active" (
    keaHaPair { singleActiveUnits = [ "kea-dhcp4-server.service" ]; }
  );

  router-ha-ntp-boundary-docs-eval = eval.mkNixosEvalCheck "router-ha-ntp-boundary-docs" [
    self.nixosModules.router-ha
    self.nixosModules.router-ntp
    self.nixosModules.router-firewall
    {
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
      };

      services.router-ntp = {
        enable = true;
        lanSubnets = [ "10.10.0.0/16" ];
      };

      services.router-firewall = {
        enable = true;
        wanInterfaces = [ "ens17" ];
        lanInterfaces = [ "ens18" ];
      };
    }
    ({ config, ... }:
      let
        ownershipDoc = builtins.readFile ../docs/router-ha-ownership.md;
      in
      {
        assertions = [
          {
            assertion = config.services.chrony.enable;
            message = "router-ntp should still enable chrony under router-ha.";
          }
          {
            assertion = !(lib.strings.hasInfix "chrony" config.services.keepalived.vrrpInstances.main.extraConfig);
            message = "router-ha should not inject Chrony ownership hooks by default.";
          }
          {
            assertion = builtins.elem 123 (config.services.router-firewall.trustedUdpPorts or [ ]);
            message = "router-ntp should keep opening trusted UDP 123 even when router-ha is enabled.";
          }
          {
            assertion =
              lib.strings.hasInfix "typed `router-ha` adapter for NTP" ownershipDoc
              && lib.strings.hasInfix "Expected policy owner" ownershipDoc;
            message = "router-ha ownership docs should explicitly record the NTP non-support stance.";
          }
        ];
      })
  ];

  router-ha-preempt-delay-eval = eval.mkNixosEvalCheck "router-ha-preempt-delay" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
        priority = 110;
        preemptDelay = 300;
      };
    }
    ({ config, ... }:
      let
        instance = config.services.keepalived.vrrpInstances.main;
      in
      {
        assertions = [
          {
            assertion = instance.state == "BACKUP";
            message = "router-ha with preemptDelay must start as BACKUP even for role = master (keepalived ignores preempt_delay on MASTER).";
          }
          {
            assertion = lib.strings.hasInfix "preempt_delay 300" instance.extraConfig;
            message = "router-ha should render preempt_delay from preemptDelay.";
          }
        ];
      })
  ];

  router-ha-preempt-default-eval = eval.mkNixosEvalCheck "router-ha-preempt-default" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
      };
    }
    ({ config, ... }:
      let
        instance = config.services.keepalived.vrrpInstances.main;
      in
      {
        assertions = [
          {
            assertion =
              instance.state == "MASTER"
              && !(lib.strings.hasInfix "preempt_delay" instance.extraConfig)
              && !(lib.strings.hasInfix "garp_" instance.extraConfig);
            message = "router-ha without preemptDelay or garp must keep the role-based MASTER start and render neither (backwards compatible).";
          }
        ];
      })
  ];

  router-ha-garp-eval = eval.mkNixosEvalCheck "router-ha-garp" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/16";
        vrrpInterface = "ens18";
        vrrpPasswordFile = "/run/keys/vrrp-password";
        garp = {
          masterDelay = 0;
          masterRepeat = 3;
          masterRefresh = 60;
          masterRefreshRepeat = 2;
        };
      };
    }
    ({ config, ... }:
      let
        conf = config.services.keepalived.vrrpInstances.main.extraConfig;
      in
      {
        assertions = [
          {
            assertion =
              lib.all (line: lib.strings.hasInfix line conf) [
                "garp_master_delay 0"
                "garp_master_repeat 3"
                "garp_master_refresh 60"
                "garp_master_refresh_repeat 2"
              ];
            message = "router-ha should render the set GARP options, including an explicit 0.";
          }
          {
            assertion = !(lib.strings.hasInfix "garp_lower_prio" conf);
            message = "unset GARP options must be left to keepalived's defaults.";
          }
        ];
      })
  ];

  # WHY: keepalived logs unknown or malformed keywords and carries on, so
  # run its own parser instead of trusting the rendered text.
  # GOTCHA: the build sandbox has no NIC, so the interface errors (and the
  # exit code they cause) are expected; any other message fails.
  router-ha-keepalived-config-test =
    pkgs.runCommand "router-ha-keepalived-config-test" { } ''
      conf=$(grep -o '/nix/store/[^" ]*keepalived.conf' ${keepalivedPreStart} | head -n1)
      for kw in garp_master_delay garp_master_repeat garp_lower_prio_delay garp_lower_prio_repeat garp_master_refresh garp_master_refresh_repeat preempt_delay; do
        grep -q "^ *$kw " "$conf" || { echo "missing $kw in $conf" >&2; exit 1; }
      done
      ${pkgs.keepalived}/bin/keepalived --config-test="$PWD/test.log" -f "$conf" -l 2> stderr || true
      cat test.log stderr > all.log
      if grep -vE "interface eth9 for vrrp_instance main doesn't exist|Non-existent interface specified|Truncating auth_pass" all.log | grep -q .; then
        echo "unexpected keepalived config messages:" >&2
        cat all.log >&2
        exit 1
      fi
      touch "$out"
    '';

  router-ha-wan-network-auto-eval = eval.mkNixosEvalCheck "router-ha-wan-network-auto" [
    self.nixosModules.router-networking
    self.nixosModules.router-ha
    {
      services.router-networking = {
        enable = true;
        wan.device = "eth0";
        wans.backup.device = "eth1";
        routedInterfaces.lan = {
          device = "eth2";
          ipv4Address = "10.10.10.2/24";
        };
      };
      services.router-ha = {
        enable = true;
        role = "backup";
        vrrpPasswordFile = "/run/keys/vrrp-password";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
        };
      };
    }
    ({ config, ... }:
      let
        nets = config.systemd.network.networks;
      in
      {
        assertions = [
          {
            assertion = config.services.router-ha.wan.network == "10-router-wan-backup";
            message = "router-ha should detect the router-networking WAN whose device is wan.interface.";
          }
          {
            assertion = nets."10-router-wan-backup".linkConfig.ActivationPolicy == "manual";
            message = "the HA-managed WAN must use ActivationPolicy=manual so only VRRP raises it.";
          }
          {
            assertion = !(nets."10-router-wan-primary".linkConfig ? ActivationPolicy);
            message = "router-ha must not touch WANs it does not manage.";
          }
        ];
      })
  ];

  router-ha-wan-network-typo-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-wan-network-typo" [
    self.nixosModules.router-ha
    {
      systemd.network.networks."10-wan" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "yes";
      };
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
          network = "10-wna";
        };
      };
    }
  ];

  router-ha-wan-network-mac-conflict-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-wan-network-mac-conflict" [
    self.nixosModules.router-ha
    {
      systemd.network.networks."10-wan" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "yes";
        linkConfig.MACAddress = "02:00:00:00:00:01";
      };
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
          network = "10-wan";
          clonedMac = "02:00:00:00:00:b0";
        };
      };
    }
  ];

  router-ha-wan-network-missing-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-wan-network-missing" [
    self.nixosModules.router-ha
    {
      services.router-ha = {
        enable = true;
        role = "master";
        vrrpPasswordFile = "/run/keys/vrrp-password";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
        };
      };
    }
  ];
  router-ha-wan-health-eval = eval.mkNixosEvalCheck "router-ha-wan-health" [
    self.nixosModules.router-ha
    {
      systemd.network.networks."10-wan" = {
        matchConfig.Name = "eth1";
        networkConfig.DHCP = "yes";
      };
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        preemptDelay = 300;
        wan = {
          enable = true;
          interface = "eth1";
          network = "10-wan";
          healthCheck = {
            enable = true;
            targets = [ "192.0.2.1" "2001:db8::1" ];
          };
        };
      };
    }
    ({ config, ... }:
      let
        ka = config.services.keepalived;
        instance = ka.vrrpInstances.main;
      in
      {
        assertions = [
          {
            assertion = instance.trackScripts == [ "router_ha_wan_health" "router_ha_wan_pin" ];
            message = "router-ha wan.healthCheck must track both the health (yield) and pin scripts.";
          }
          {
            # INVARIANT: weight 0 makes a failed check FAULT the instance,
            # which is what bypasses the peer's preempt_delay.
            assertion = ka.vrrpScripts.router_ha_wan_health.weight == 0 && ka.vrrpScripts.router_ha_wan_pin.weight == -253;
            message = "router_ha_wan_health must use weight 0 (FAULT) and router_ha_wan_pin weight -253 (priority 1).";
          }
          {
            assertion = lib.strings.hasInfix "-W 0.800" (builtins.readFile ka.vrrpScripts.router_ha_wan_health.script);
            message = "router_ha_wan_health must probe targets with the fractional timeoutMs.";
          }
        ];
      })
  ];

  router-ha-wan-health-default-off-eval = eval.mkNixosEvalCheck "router-ha-wan-health-default-off" [
    self.nixosModules.router-ha
    {
      systemd.network.networks."10-wan".matchConfig.Name = "eth1";
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
          network = "10-wan";
        };
      };
    }
    ({ config, ... }: {
      assertions = [
        {
          assertion = config.services.keepalived.vrrpInstances.main.trackScripts == [ ] && config.services.keepalived.vrrpScripts == { };
          message = "router-ha must not add WAN health tracking unless wan.healthCheck.enable is set.";
        }
      ];
    })
  ];

  router-ha-wan-health-timeout-fails-eval = eval.mkNixosEvalFailureCheck "router-ha-wan-health-timeout" [
    self.nixosModules.router-ha
    {
      systemd.network.networks."10-wan".matchConfig.Name = "eth1";
      services.router-ha = {
        vrrpPasswordFile = "/run/keys/vrrp-password";
        enable = true;
        role = "master";
        virtualIp = "10.10.10.1/24";
        vrrpInterface = "eth2";
        wan = {
          enable = true;
          interface = "eth1";
          network = "10-wan";
          healthCheck = {
            enable = true;
            interval = 1;
            timeoutMs = 1000;
          };
        };
      };
    }
  ];
}
