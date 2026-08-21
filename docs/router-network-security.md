# Router Network Security Sensors

`router-network-security` is a bounded wrapper for opt-in packet security
sensors on router hosts.

It currently provides consumer-facing options for:

- Suricata
- Snort 3
- Zeek

The module does **not** try to become a full IDS/IPS management plane. Its job
is narrower:

- derive capture interfaces from existing router interface data when possible
- derive a reasonable `HOME_NET` / local network view from routed IPv4 CIDRs
- expose simple on/off and command-shaping options for each engine
- keep the engine-specific boundary honest where nixpkgs support differs

## Current Engine Boundary

### Suricata

Uses the upstream NixOS `services.suricata` module from nixpkgs and fills in
capture interfaces plus `vars.address-groups.HOME_NET`.

This is the strongest-integrated path today.

### Snort 3

Uses the packaged `pkgs.snort` binary with a repo-native systemd wrapper.

The wrapper:

- uses one of the packaged Lua profiles
- passes derived interfaces with repeated `-i`
- injects `HOME_NET` and `EXTERNAL_NET` through `--lua`
- keeps the consumer surface bounded to DAQ mode, alert mode, and extra args

It is intentionally lighter than a full Snort policy-management layer.

### Zeek

Uses the packaged `pkgs.zeek` binary with one systemd service per capture
interface because the `zeek` CLI only accepts one `-i` interface at a time.

The wrapper defaults to loading the `local` policy script and writes per-sensor
status files plus logs.

## Example

```nix
services.router-network-security = {
  enable = true;

  suricata.enable = true;

  snort = {
    enable = true;
    profile = "security";
    daqMode = "passive";
  };

  zeek.enable = true;
};
```

With router interface data already declared elsewhere, the module will derive
capture interfaces automatically. If you want to pin them explicitly:

```nix
services.router-network-security = {
  enable = true;
  interfaces = [ "wan0" "lan0" ];
  homeNetworks = [ "10.10.10.0/24" "192.168.50.0/24" ];
  suricata.enable = true;
};
```

## Constraints

- The module does not manage SPAN/TAP topology for you.
- Running multiple full-packet engines at once can be expensive; consumer-side
  tuning is still your responsibility.
- Suricata currently has the cleanest nixpkgs-native integration.
- Snort and Zeek are intentionally first-slice wrappers, not full policy
  orchestration layers.
