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
capture interfaces, `vars.address-groups.HOME_NET`, and an EVE JSON output.

This is the strongest-integrated path today.

#### Event output (EVE JSON)

The upstream module defaults `settings.outputs` to `null`. Without an output,
Suricata inspects traffic but **records nothing**: `/var/log/suricata` stays
empty and EveBox shows no events, while every unit reports `active`.
`suricata.eveLog` (on by default) fills this gap:

| Option | Default | Meaning |
| --- | --- | --- |
| `suricata.eveLog.enable` | `true` | generate an `eve-log` output |
| `suricata.eveLog.file` | `/var/log/suricata/eve.json` | EVE file; EveBox tails it by default |
| `suricata.eveLog.types` | `alert anomaly http dns tls ssh flow` | event types to log |
| `suricata.eveLog.retentionDays` | `7` | daily rotated files kept by logrotate |

Notes:

- Suricata never rotates its own logs. With `flow` and `dns` events enabled,
  `eve.json` grows by tens to hundreds of MB per day on a busy LAN. The module
  adds a daily `logrotate` stanza (`copytruncate`, compressed) run as
  Suricata's `run-as` account.
- If `eveLog.file` is outside `settings.default-log-dir`, the module creates
  its directory and adds it to the unit's `ReadWritePaths`. The upstream unit
  uses `ProtectSystem=strict` and only allows `default-log-dir`.
- Setting `suricata.extraSettings.outputs` replaces the generated output
  entirely. Rotation is then up to you.

Quick check that events are flowing:

```sh
sudo tail -n 3 /var/log/suricata/eve.json | jq -c '{event_type, src_ip, dest_ip}'
```

#### EveBox

`suricata.evebox.enable` runs EveBox on `127.0.0.1:5636` with `--no-auth`.
Put it behind a reverse proxy that restricts access (for example Caddy with a
`remote_ip` matcher for LAN/Tailnet ranges). Do not expose it directly.

#### Capture placement

Suricata in `pcap`/`af-packet` mode is passive: it reads a copy of the packets
and is not in the forwarding path, so a crashed sensor does not stop routing.
It can only see traffic on the router's own interfaces. Running it on another
host (a VM or a home server) needs port mirroring (SPAN/TAP), which this
module does not manage. On a single router, run Suricata on the router.

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

  suricata = {
    enable = true;
    evebox.enable = true;   # UI on 127.0.0.1:5636, proxy it
  };

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
