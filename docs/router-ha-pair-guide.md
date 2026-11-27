# Router HA Pair Guide

This is the shortest practical guide for setting up a two-node
`router` / `router-backup` style VRRP pair with `nix-router-optimized`.

If you are not sure where to start:

1. make `router-ha` own the shared LAN VIP and WAN interface
2. keep Chrony shared on both nodes
3. only place clearly single-owner units in `singleActiveUnits`
4. test failover on the backup node before touching the primary

This guide is intentionally narrower than "full appliance HA." It shows the
currently validated pattern, not every possible topology. Where the design
comes from, and how it compares with OPNsense, NethSecurity and VyOS pairs, is
in [`router-ha-prior-art.md`](./router-ha-prior-art.md).

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

DHCP identity: with `clonedMac` set, `wan.sharedDhcpIdentity` (on by
default) gives both nodes' WAN the same DHCPv4 and DHCPv6 identity: a
link-layer DUID built from the cloned MAC (`00:01:<mac>`) and an IAID from
its last four bytes. Without it each node sends its own machine-id DUID, and
an ISP that binds the lease or the delegated prefix to the DUID hands the
new master a different prefix, so LAN clients renumber. Enabling it changes
the DUID once, which can move the delegated prefix at the next renewal; set
it to `false` to keep the old DUID. Values you set yourself in the WAN
network's `dhcpV4Config`/`dhcpV6Config` win (`mkDefault`).

Lease release: demotion runs `networkctl down`, which takes the WAN link down
before systemd-networkd's DHCP client stops, so no DHCP RELEASE reaches the
ISP and the new master renews the binding the old one held.
`vm-router-ha-wan-failover` checks that the simulated ISP sees no RELEASE
across failover and fail-back. This matters for ISPs that hold a released
address for a cooldown (see [`router-ha-prior-art.md`](./router-ha-prior-art.md)).

A reconfigure is different: when networkd reapplies the WAN `.network` while
the link is up (a deploy that changes it), it restarts the DHCP clients, and
with networkd's default `SendRelease=yes` they release first. router-ha
therefore defaults `SendRelease=no` for DHCPv4 and DHCPv6 on the WAN network.
Set it on the network to override. The VM test reconfigures the MASTER's WAN
and checks that the address and the delegated prefix stay, with no RELEASE.

With `clonedMac`, router-ha also disables duplicate address detection on
the WAN (`IPv6DuplicateAddressDetection = 0`). On a planned handover the old
master still holds the shared link-local address for a moment; DAD on the
new master then marked it `dadfailed` permanently and DHCPv6 never started.
VRRP already keeps the clone on one node.

`vm-router-ha-wan-failover` checks that the simulated ISP, which binds PD
to the DUID and IAID, delegates the same /56 to both nodes across failover
and fail-back. With the shared identity off, the peer gets a different /56.

DHCPv6 and prefix delegation also start only
after the new master hears a Router Advertisement; most ISPs answer the
router solicitation at once, but one that only sends slow periodic RAs
delays IPv6 after a failover. `DHCPv6Config.WithoutRA = "solicit"` on the
WAN network removes that dependency.

## Transition Order

keepalived would normally start a separate notify script for every state
change without waiting for the previous one, so a MASTER immediately followed
by FAULT could raise the WAN after the FAULT script had taken it down.
router-ha instead uses keepalived's `vrrp_notify_fifo`: one long-running
reader (`/run/router-ha/notify.fifo`) applies MASTER, BACKUP, FAULT and STOP
one at a time, in the order keepalived sent them. Single-active units are
started and stopped with `--no-block`, so a slow unit cannot hold up the next
transition. `vm-router-ha-pair` feeds MASTER and FAULT back to back and checks
that the node ends in FAULT with its WAN and owned units down.

A keepalived reload (`systemctl reload keepalived`) replaces the reader.
keepalived replays BACKUP and FAULT to the new reader
(`fifo_write_vrrp_states_on_reload`) but not MASTER, and the reload can kill
a MASTER transition half-way, with the WAN down. The MASTER script therefore
marks `/run/router-ha/master-pending` while it runs; a new reader that finds
the marker while the node holds the VIP runs the MASTER transition again. The
transition scripts are idempotent, so repeating one is safe.

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

The delay also applies after a crash: keepalived's unit restarts it
(`Restart=always`), and the restarted daemon comes back as BACKUP and waits.
It applies after the master's LAN link returns from FAULT and after a
reboot too; through boot the WAN stays down (`ActivationPolicy=manual`).

## WAN Health Tracking (`wan.healthCheck`)

VRRP adverts travel on the LAN, so by default a master whose WAN is dead
(the DHCP lease never came back, a NIC or cable fails with carrier still up,
`networkctl reconfigure` failed) keeps the VIP. Enable the health check on
both nodes to hand over in that case:

```nix
services.router-ha.wan.healthCheck = {
  enable = true;
  # targets = [ "1.1.1.1" "9.9.9.9" ];  # default: ARP the WAN's default gateway
};
```

While a node is master it probes the WAN every `interval` seconds (default
1, with a `timeoutMs` of 500; the probe must leave at least 300 ms of the
interval for the check's own start-up, or keepalived skips overlapping
runs). After `failures` consecutive failures
(default 3), and only once `startupGraceSec` (default 30) has passed since
promotion so DHCP can finish, it:

1. **yields**: the check enters keepalived FAULT, which sends a priority-0
   advert, so the peer takes over at once. This bypasses `preemptDelay`; a
   plain priority drop would make the peer wait `preemptDelay` first;
2. **pins** its own priority to 1 (`/run/router-ha/wan-penalty` holds `1`),
   so it does not preempt straight back.

A pinned node never yields again. If the peer's WAN is bad too (the ISP
itself is down), the peer yields back to the pinned node, which stays
master: the LAN VIP, DHCP and DNS stay up on one node instead of both
sitting in FAULT. When the peer is missing, the yield still costs a few
seconds: the node leaves FAULT after about 3 s and reclaims the VIP after
keepalived's master-down timer, then stays master pinned. The check needs
`priority` below 255, because keepalived never lowers address-owner
priority.

A backup's WAN is down, so it cannot see a repair. After `retryAfterSec`
(default 900; `null` disables retries) the pin is lifted and the node
preempts again after `preemptDelay` to re-test; if the WAN is still bad it
yields again. During an ISP outage that hits both nodes, each retry moves
the VIP twice. Restarting keepalived also clears the pin. A master that
passes a check clears its own pin.

The default probe (ARP for the IPv4 default gateway) catches node-local
faults without depending on remote hosts. `targets` pings addresses
instead, in parallel, and also catches outages past the ISP gateway, which
usually hit both nodes alike. Point-to-point WANs such as PPPoE have no
gateway to ARP for; with no targets set, a default route on the WAN counts
as healthy, so set `targets` there.

There is one VRRP instance (on the LAN) and the WAN follows it through the
notify scripts, so no `vrrp_sync_group` is needed. keepalived in nixpkgs is
built without BFD, so `track_bfd` is not an option.

The VM test `vm-router-ha-wan-health` (with `preemptDelay = 10`) drops all
WAN traffic on the master with carrier up. The peer becomes master within
5 s (about 4 s in the VM), the pinned node stays backup past
`preemptDelay`, and it takes over again only after `retryAfterSec` plus
`preemptDelay`. With the ISP dark for both nodes, the pinned node ends up as
the one stable master. A mutation that drops the yield fails the 5 s bound.

## Tested Lifecycle

The VM test `vm-router-ha-pair` runs two routers with `preemptDelay = 10`
and a stand-in unit in `singleActiveUnits`, and checks after every
transition that exactly one node holds the VIP, the WAN and the unit
(sampled for 5 s):

| Event on the MASTER | Measured in the VM |
|---|---|
| keepalived killed (SIGKILL) | peer is MASTER after about 4 s |
| LAN link down | node goes to FAULT, peer takes over |
| reboot | peer takes over; the node boots as BACKUP with its WAN down |
| recovery from any of the above | node waits `preemptDelay` as BACKUP, then takes everything back |
| upstream dark, carrier up (`wan.healthCheck`, test `vm-router-ha-wan-health`) | peer is MASTER after about 4 s, despite `preemptDelay` |

DNS zone ownership under `zoneReplication.ha` has its own VM test,
`vm-router-technitium-zone-ha`; see
[`router-technitium-automation.md`](./router-technitium-automation.md#following-vrrp-zonereplicationha).

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
| DDNS updater | `router-ddns.ha.singleActiveOwner` | public identity should follow the active node |
| UPnP / NAT-PMP | `router-upnp.ha.singleActiveOwner` | mappings belong to the node holding the WAN |
| IPv6 RAs on the LAN | `router-ha.routerAdvertisements.mode = "vrrp-owner"` | clients must not route IPv6 to a backup; the MASTER advertises from `virtualLinkLocal` so a dead MASTER leaves no stale route |
| Kea D2 | `router-kea.ddns.ha.mode` | updates must reach the zone primary |
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

router-ha sets `KeepConfiguration=static` on the VRRP interface's
`.network` (`vrrpNetwork`, detected for router-networking). Without it a
networkd restart, for example during a deploy that changes network config,
deletes the VIP and the MASTER briefly fails over. If your LAN `.network` is
not managed by router-networking, set `vrrpNetwork` to its attribute name.

Evaluation fails until each of these services has an owner. See
[`router-ha-ownership.md`](./router-ha-ownership.md) for what each option does.
`singleActiveUnits` remains for your own units without a typed option.

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
