{ lib }:

with lib;

let
  cidrAddress = cidr: head (splitString "/" cidr);
  cidrPrefixLen = cidr: toInt (last (splitString "/" cidr));
in
{
  mkTaygaAdapter = {
    interfaceName,
    ipv4Pool,
    ipv6Prefix,
    ipv4RouterAddr,
    ipv6RouterAddr,
    stateDirectory,
    serviceUnit,
  }:
  rec {
    kind = "tayga";

    runtime = {
      inherit interfaceName stateDirectory serviceUnit;
    };

    firewall = {
      forwardInputInterface = interfaceName;
    };

    tayga = {
      serviceAttrs = {
        enable = true;
        ipv4 = {
          address = ipv4RouterAddr;
          router.address = ipv4RouterAddr;
          pool = {
            address = cidrAddress ipv4Pool;
            prefixLength = cidrPrefixLen ipv4Pool;
          };
        };
        ipv6 = {
          router.address = ipv6RouterAddr;
          pool = {
            address = cidrAddress ipv6Prefix;
            prefixLength = cidrPrefixLen ipv6Prefix;
          };
        };
      };

      configText = ''
        tun-device ${interfaceName}
        ipv4-addr ${ipv4RouterAddr}
        ipv6-addr ${ipv6RouterAddr}
        prefix ${ipv6Prefix}
        dynamic-pool ${ipv4Pool}
        data-dir ${stateDirectory}
      '';
    };
  };
}
