{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.router-sqm;

  sqmInterfaceModule = types.submodule {
    options = {
      device = mkOption {
        type = types.str;
        description = "Interface device name (e.g., eth0).";
      };

      bandwidthIngress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "100mbit";
        description = "Ingress (download) bandwidth limit. Set to ~95% of your actual line speed.";
      };

      bandwidthEgress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "20mbit";
        description = "Egress (upload) bandwidth limit. Set to ~95% of your actual line speed.";
      };

      cakeArgs = mkOption {
        type = types.str;
        default = "nat triple-isolate rtt 100ms";
        description = "Extra arguments for the CAKE qdisc. 'nat' is usually required for routers.";
      };
    };
  };
in
{
  options.services.router-sqm = {
    enable = mkEnableOption "Smart Queue Management (SQM) with CAKE";

    interfaces = mkOption {
      type = types.listOf sqmInterfaceModule;
      default = [ ];
      description = "List of interfaces to apply SQM/CAKE queuing to.";
    };
  };

  config = mkIf cfg.enable {
    # We use a systemd service to apply the tc commands because networkd
    # qdisc support is limited/static and CAKE is often best applied via tc.
    systemd.services.apply-sqm = {
      description = "Apply SQM/CAKE traffic shaping";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = concatMapStringsSep "\n" (iface: ''
        echo "Applying SQM to ${iface.device}..."
        # Clear existing qdiscs
        ${pkgs.iproute2}/bin/tc qdisc del dev ${iface.device} root 2>/dev/null || true
        ${pkgs.iproute2}/bin/tc qdisc del dev ${iface.device} ingress 2>/dev/null || true

        # Egress (root)
        ${if iface.bandwidthEgress != null then ''
          ${pkgs.iproute2}/bin/tc qdisc add dev ${iface.device} root handle 1: cake bandwidth ${iface.bandwidthEgress} ${iface.cakeArgs}
        '' else ''
          ${pkgs.iproute2}/bin/tc qdisc add dev ${iface.device} root handle 1: cake ${iface.cakeArgs}
        ''}

        # Ingress (using ifb for proper shaping if needed, but modern CAKE on ingress is also possible)
        # For simplicity in this first version, we apply CAKE to root.
        # Note: True ingress shaping usually requires an IFB device. 
        # For now, we focus on Egress which is where Bufferbloat is most severe.
      '') cfg.interfaces;
    };
  };
}
