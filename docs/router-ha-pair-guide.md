# Router HA Pair Guide

This is the shortest practical guide for setting up a two-node
`router` / `router-backup` style VRRP pair with `nix-router-optimized`.

If you are not sure where to start:

1. make `router-ha` own the shared LAN VIP and WAN interface
2. keep Chrony shared on both nodes
3. only place clearly single-owner units in `singleActiveUnits`
4. test failover on the backup node before touching the primary

This guide is intentionally narrower than "full appliance HA." It shows the
currently validated pattern, not every possible topology.

## What This Pattern Does

- gives both nodes a shared VRRP identity
- lets the promoted node own WAN activity
- lets the promoted node start specific single-owner systemd units
- keeps selected services shared on both nodes

## What This Pattern Does Not Do Automatically

- it does **not** make every LAN-facing service follow promotion by default
- it does **not** define the right ownership model for Chrony automatically
- it does **not** imply Kea DHCP HA clustering; that remains a separate choice

See [`router-ha-ownership.md`](./router-ha-ownership.md) for the support
boundary and [`router-dhcp-single-active.md`](./router-dhcp-single-active.md)
for the current DHCP posture guidance.

## Copyable Shape

The repo ships a schematic sample in
[`examples/router-ha-pair-example.nix`](../examples/router-ha-pair-example.nix).
Treat it as a starting point, not a finished deployment.

The example is split into:

- `common`: settings shared by both nodes
- `master`: the preferred primary node
- `backup`: the standby node

The important idea is to keep the shared settings in one place and only vary
role/priority per node.

## Delayed Fail-Back (`preemptDelay`)

By default the node with `role = "master"` starts as MASTER and takes the VIP
back the moment it returns. Set `services.router-ha.preemptDelay` (seconds,
0–1000) on every node to make a recovered higher-priority node wait as
BACKUP before preempting:

```nix
services.router-ha = {
  priority = 110;      # preferred node; peers use lower priorities
  preemptDelay = 300;  # wait 5 minutes before taking the VIP back
};
```

With `preemptDelay` set, every node starts as BACKUP and priority alone
picks the master (keepalived ignores `preempt_delay` on an instance that
starts as MASTER). Failover away from a dead master is not delayed; only the
return is. Each fail-back moves the single-active units (WAN, DHCP, DDNS),
so fewer of them means fewer short outages when a primary flaps.

## Recommended Ownership Split

| Service area | Recommended starting policy | Why |
|---|---|---|
| `services.router-ha.wan` | promotion-aware | the active router should own WAN activity |
| LAN VIP | promotion-aware | clients need one stable gateway IP |
| DDNS updater | promotion-aware | public identity should follow the active node |
| Chrony / `router-ntp` | shared on both nodes | standby time sync is operationally useful |
| Suricata / observability | often shared | passive visibility can stay useful on standby |
| DHCP / other LAN services | only promote after explicit testing | these are the easiest place to break clients |

## Values You Must Replace

At minimum, replace these values from the example:

- `10.10.10.1/24` with your shared LAN VIP and prefix
- `lan0` with your real LAN interface
- `wan0` with your real WAN interface
- `02:00:00:00:00:01` with your WAN-side cloned MAC if your ISP expects one
- `/run/secrets/router-vrrp-password` with the path your secret manager
  decrypts the shared VRRP password to (see below)
- `10.10.10.0/24` with your real LAN subnet

If you use `router-ddns`, keep `inadyn.service` in `singleActiveUnits`. Add the
matching timer unit only if your evaluated system actually exposes it under that
name.

## VRRP Authentication

`services.router-ha.vrrpPasswordFile` names a file holding the shared VRRP
password. It is loaded as a systemd credential by `router-ha-vrrp-secret`,
which renders `/run/router-ha/vrrp-secret.env` (mode 0600); keepalived
substitutes it into `/run/keepalived/keepalived.conf` at start. The password
never enters the Nix store. A restart of keepalived re-reads the file.

- Use the same file content on both nodes (agenix, sops-nix or clan vars).
- Keepalived uses only the first 8 characters; the unit logs a note when the
  file is longer.
- Allowed characters: printable ASCII without whitespace, quotes, backslash,
  `$`, `#` or `!`. The unit fails (and keepalived does not start) otherwise.
- VRRPv2 `PASS` authentication travels in clear text. It prevents accidental
  cross-talk between VRRP groups on a shared segment; it does not stop an
  attacker on the LAN. Run VRRP only on a trusted link.

### Migrating from `vrrpPassword`

There is no default password any more, and exactly one of
`vrrpPasswordFile` or `vrrpPassword` must be set, or evaluation fails. A pair
where one node authenticates and the other does not elects two masters, so
this is deliberately not a silent change.

- If you relied on the old default `nix-router-ha`, write `nix-rout` (the
  first 8 characters, which is all keepalived ever used) to your secret file,
  set `vrrpPasswordFile` on both nodes, and deploy them. The wire format is
  unchanged, so the nodes keep agreeing during a rolling deploy. Rotate to a
  new value afterwards by updating the file on both nodes and restarting
  keepalived on each.
- `vrrpPassword = "..."` still works but prints a warning, because the value
  is written to the world-readable Nix store.

## Minimal Flake Layout

One practical structure is:

```nix
{
  inputs.router-optimized.url = "github:deepwatrcreatur/nix-router-optimized";

  outputs = { self, nixpkgs, router-optimized, ... }: {
    nixosConfigurations.router = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        router-optimized.nixosModules.router-ha
        router-optimized.nixosModules.router-ntp
        router-optimized.nixosModules.router-firewall
        (import ./router-ha-common.nix)
        {
          services.router-ha.role = "master";
          services.router-ha.priority = 100;
        }
      ];
    };

    nixosConfigurations.router-backup = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        router-optimized.nixosModules.router-ha
        router-optimized.nixosModules.router-ntp
        router-optimized.nixosModules.router-firewall
        (import ./router-ha-common.nix)
        {
          services.router-ha.role = "backup";
          services.router-ha.priority = 90;
        }
      ];
    };
  };
}
```

Then keep the shared HA settings in `router-ha-common.nix`.

## First Safe Test Plan

Do not start by switching both nodes.

1. build both nodes successfully
2. deploy to the backup node first
3. confirm the backup stays in `BACKUP` state
4. confirm shared services still behave as expected
5. only then test promotion behavior for the units you explicitly handed to
   `singleActiveUnits`

For risky live changes, use [`router-apply-safety.md`](./router-apply-safety.md).
