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

## WAN Ownership

Only the VRRP master has its WAN link up. router-ha sets
`ActivationPolicy=manual` on the WAN's `.network` (detected automatically
for `router-networking` WANs, otherwise set `services.router-ha.wan.network`),
so systemd-networkd never raises the WAN by itself, at boot or when it
restarts during a `nixos-rebuild switch`.

- **Promotion:** set the cloned MAC (while the link is down), then
  `networkctl up` and `networkctl reconfigure` on the WAN only. DHCPv4,
  DHCPv6 and prefix delegation start fresh with the cloned MAC.
- **Demotion and fault:** `networkctl down` on the WAN.
- LAN, management and systemd-networkd itself are never restarted. Earlier
  versions restarted systemd-networkd on promotion, which bounced every link
  at the moment of failover.

Evaluation checks that `wan.network` names a network whose
`matchConfig.Name` is `wan.interface` (a typo would otherwise create a new,
empty network and leave the real WAN automatic), and that the network does
not set `MACAddress` to something other than `clonedMac`: `networkctl
reconfigure` re-applies it and would undo the clone before DHCP starts.

A failed `networkctl reconfigure` does not demote the node: keepalived stays
MASTER without a working WAN, as it did with the earlier networkd restart.
Tracking WAN health in VRRP priority is not implemented yet.

Do not set `ActivationPolicy=always-down` on the WAN of an HA node (a common
way to park a cold standby): `networkctl up` refuses always-down links, and
the module system reports the conflicting definition.

The VM test `vm-router-ha-wan-failover` checks all of this on two routers
with a simulated ISP (DHCPv4 tied to the cloned MAC, DHCPv6 with prefix
delegation): election, failover, fail-back, a networkd restart on the
standby, and no link or static-address change on LAN or management. A planned
failover there takes about 4 s from `systemctl stop keepalived` to the new
master holding the VIP, the IPv4 lease and a delegated prefix.

IPv6 note: the DHCPv6 DUID differs per node, so an ISP that pins the
delegated prefix to the DUID may hand the new master a different prefix,
and LAN clients then renumber.

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

## Gratuitous ARP and NA (`garp`)

On promotion keepalived sends gratuitous ARP (IPv4) and unsolicited
neighbour advertisements (IPv6) for the VIP, so clients, switches and
hypervisor bridges learn its new MAC. No arping or ndisc6 scripts are needed.
`services.router-ha.garp` exposes keepalived's per-instance settings; each is
`null` by default, which keeps keepalived's own default:

| Option | Keepalived keyword | Keepalived default |
|---|---|---|
| `masterRepeat` | `garp_master_repeat` | 5 messages per burst |
| `masterDelay` | `garp_master_delay` | second burst after 5 s (0 = none) |
| `lowerPrioRepeat` / `lowerPrioDelay` | `garp_lower_prio_*` | same as the master values |
| `masterRefresh` | `garp_master_refresh` | 0 (no periodic refresh) |
| `masterRefreshRepeat` | `garp_master_refresh_repeat` | 1 |

Measure before you tune. During a failover rehearsal, watch the VIP from a
client (`ping -D <vip>` and `ip neigh show <vip>`) and from the switch or
Proxmox bridge MAC table (`bridge fdb show | grep <vip-mac>`). Raise
`masterRepeat` if clients miss the first burst. Set `masterRefresh` (for
example 60) only if a switch or bridge ages out the VIP's entry while the
master is idle.



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
- Give a runtime string path such as `"/run/agenix/router-vrrp-password"`.
  A Nix path literal (`./vrrp-password`) would copy the secret into the
  store, so evaluation rejects any path under `/nix/store`.
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
