{
  self,
  lib,
  eval,
  pkgs,
}:

let
  topology = import ../lab/nspawn/topologies/ha-basic/topology.nix;
  labPlan = builtins.readFile ../docs/router-ha-lab-plan.md;
  labReadme = builtins.readFile ../lab/README.md;
in
{
  router-ha-lab-topology-eval = pkgs.runCommand "router-ha-lab-topology-eval" { } ''
    if [ "${topology.name}" != "ha-basic" ]; then
      echo "unexpected topology name: ${topology.name}" >&2
      exit 1
    fi

    if [ "${toString (builtins.length (builtins.attrNames topology.nodes))}" != "4" ]; then
      echo "expected four lab nodes" >&2
      exit 1
    fi

    if ${if topology.supportBoundary.automaticDhcpFailover then "true" else "false"}; then
      echo "phase-1 lab must not claim automatic DHCP failover" >&2
      exit 1
    fi

    if [ "${topology.networks.lan.vip}" != "192.0.2.1/24" ]; then
      echo "unexpected lab VIP" >&2
      exit 1
    fi

    touch "$out"
  '';

  router-ha-lab-docs-boundary-eval = eval.mkNixosEvalCheck "router-ha-lab-docs-boundary" [
    ({ ... }: {
      assertions = [
        {
          assertion =
            lib.strings.hasInfix "systemd-nspawn" labPlan
            && lib.strings.hasInfix "NixOS VM tests" labPlan
            && lib.strings.hasInfix "control-plane harness" labPlan;
          message = "router-ha-lab-plan should record the staged nspawn-first boundary clearly.";
        }
        {
          assertion =
            lib.strings.hasInfix "no physical NIC attachment" labReadme
            && lib.strings.hasInfix "lab-only bridge" labReadme;
          message = "lab README should record the host-local safety boundaries.";
        }
      ];
    })
  ];
}
