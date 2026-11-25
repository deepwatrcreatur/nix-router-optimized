# Router HA Prior Art: One Dynamic WAN IP, Two Routers

This note records what other projects do when two routers share **one
DHCP-assigned public IPv4 address and one delegated IPv6 prefix** from a
residential ISP. It also records which of their ideas `router-ha` adopted or
rejected, and why. It exists so a reader can trace a design decision back to
its source and the evidence for it.

How it was made: on 2026-11-25, before the first live VRRP drill on the
homelab pair (`elitedesk` and `router`, nix-clan-homelab bead `nch-sny.36`),
the operator asked whether we had borrowed all we could from OPNsense and
others. The sources below were searched for and read on that date. Forum and
gist comments are community reports, not vendor documentation; they are
marked as such. Platform comparisons (CARP versus VRRP, pfsync versus
conntrackd) are in [`FREEBSD-OPNSENSE-COMPARISON.md`](./FREEBSD-OPNSENSE-COMPARISON.md)
and [§3 of the ecosystem plan](./ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md#3-comparative-ecosystem-survey);
this note covers only the single-WAN-address problem and its neighbours.

## The problem

VRRP and CARP float a LAN address between nodes. A residential WAN address
cannot float that way: the ISP leases it to one client, usually bound to the
client's MAC address and DHCP client identity (DUID, IAID, option 61), and the
delegated /56 is bound to the DHCPv6 DUID and IAID. A backup that asks for a
lease with its own identity gets a different address, or nothing until the
old lease expires.

## What others do

| Source | WAN mechanism | DHCP server for the LAN | State sync | Notes |
| --- | --- | --- | --- | --- |
| OPNsense, CARP hook script ([spali gist][spali]) | WAN enabled only on the CARP master; operators clone the same WAN MAC on both nodes | not covered | pfsync | The most common community answer. Comments: disabling the interface did not clear states and routes (later versions also disable the WAN gateway); `dhclient -r` or killing dhclient on BACKUP in some forks; the hook broke across OPNsense upgrades (25.1.10+, 26.1) |
| OPNsense, os-carp-vip-dhcp plugin ([toreamun][toreamun]) | A daemon holds the DHCP lease for the CARP virtual MAC `00:00:5e:00:01:<vhid>`; WANs keep link-local addresses for adverts | not covered | pfsync | Needs an ISP that serves the virtual MAC. Pitfalls it lists: ISPs that bind the lease to the first MAC seen; client-id (option 61) mismatch means silence until the old lease expires; one-MAC-per-port lines may need a modem reset; cutting over from a live DHCP WAN needs a release and cooldown; test by pulling the link or stopping the VM, not by `ifconfig down` |
| NethSecurity `ns-ha` ([docs][nethsec]), OpenWrt + keepalived | WAN devices created disabled on the backup; enabled on NOTIFY_MASTER | dnsmasq runs on the master only; no lease sync | conntrackd | Disables DDNS, SNMP, VPNs, IDS and cron jobs on the backup. Serialises notify hooks with a lock (`ns_lock_timeout`, 120 s suggested, because some services stop slowly). Config is rsynced from the primary |
| VyOS ([HA][vyos-ha], [conntrack-sync][vyos-ct]) | Transition scripts; health-check scripts can force FAULT | DHCPv6 server not supported with HA (1.4, forum) | conntrack-sync tied to a sync group | A cable-ISP user's scripts toggled the WAN by committing config, which bounced VRRP itself (forum, unresolved) |
| ISC Kea ([HA strategies][isc-ha]) | n/a | HA hook; hot-standby is ISC's preferred mode | lease updates between peers | pfSense users report instability with Kea HA after upgrades, and some run a single node instead (forum) |
| keepalived home pair ([jwhitham][jwhitham]) | LAN VIP only; backup has its own uplink | not covered | none | Health checks are not automatic (`vrrp_script` with `rise`/`fall` hysteresis); sessions drop on failover and again on fail-back |
| NixOS | — | — | — | Searches found only basic `services.keepalived` examples ([wiki][nixos-wiki]) and router repos without WAN failover. No NixOS project handling a single dynamic WAN address was found |

## How `router-ha` compares

`router-ha` uses the same mechanism as the OPNsense hook script, built so the
known failure modes cannot happen:

| Concern from prior art | `router-ha` | Where |
| --- | --- | --- |
| WAN must be active on one node only | `ActivationPolicy=manual`; only `notify_master` raises the WAN; demotion and FAULT take it down. The WAN also stays down through boot and networkd restarts | [pair guide, WAN Ownership](./router-ha-pair-guide.md#wan-ownership), #155 |
| Toggling the WAN must not disturb the rest (VyOS commit bounce, OPNsense reconfigure) | `networkctl up`/`reconfigure` on the WAN only; networkd is never restarted | #155 |
| The ISP binds the lease to the MAC and client identity | Cloned MAC set while the link is down; `sharedDhcpIdentity` gives both nodes the same DUID and IAID, so the same /56 comes back | #155, #162 |
| Duplicate address detection on the shared link-local address | DAD off on a cloned WAN | #162 |
| A master with a dead WAN keeps the VIP | `wan.healthCheck` yields through FAULT and pins priority | #161 |
| Flapping on recovery | `preemptDelay` | #144 |
| Clients' ARP and switch tables after failover | keepalived gratuitous ARP and NA settings | #154 |
| Services that must run on one node (NethSecurity's list) | Typed `ha.singleActiveOwner` options and `singleActiveUnits`; started and stopped with `--no-block`, so a slow unit cannot stall the transition | [ownership](./router-ha-ownership.md), #156 |
| DNS zones written by DHCP | `zoneReplication.ha` promotes and demotes zones with VRRP | #148, #149 |
| Configuration drift between nodes | Not needed: both nodes build from the same Nix expression | — |

The virtual-MAC keeper design was **rejected**: it needs the ISP to lease an
address to a MAC the operator does not control, and a residential cable modem
normally serves one CPE MAC. A cloned MAC that only one node presents at a
time avoids both the ISP question and switch MAC-table flapping.

## Adopted from this review

The changes this review led to. Each is a separate change with its own VM
test; until it lands, its section here describes the plan.

1. **Kea hot-standby mode** (bead `router-p6q`). `router-kea.dhcp4.ha` only offered
   `load-balancing`. ISC prefers hot-standby, and it fits a preferred node plus
   a spare: the standby answers only when the primary stops responding.
2. **Ordered notify handling** (bead `router-pve`). keepalived starts a notify script for each
   transition without waiting for the previous one. If MASTER is followed
   quickly by FAULT, the FAULT script's `networkctl down` can run before the
   MASTER script's `networkctl up`, leaving the WAN up on a FAULT node.
   NethSecurity serialises its hooks with a lock; keepalived's `notify_fifo`
   gives the same guarantee and also keeps the order.
3. **No DHCP release on demotion, as an option** (bead `router-u4n`). OPNsense users found that
   releasing or changing a lease makes some ISPs hold the address for a
   cooldown. With the same MAC and identity on both nodes, keeping the binding
   lets the new master renew the same lease. Off by default, because whether a
   given ISP prefers a release is not known in advance.
4. **Drill with real failures.** Pull the WAN cable and cut power during
   rehearsals, not only `systemctl stop keepalived` (toreamun's advice).

## Deferred

- **conntrackd.** Every source pairs VRRP or CARP with state sync, but it only
  helps once plain failover is proven on the hardware. See
  [ecosystem plan §0.4](./ECOSYSTEM-RESEARCH-AND-IMPROVEMENT-PLAN.md#04-verdicts-on-the-4-proposals).
- **Lease release and cooldown behaviour of a specific ISP.** Measure it
  during the live drill; the VM test's ISP cannot model it.

## Sources

All read 2026-11-25.

- [spali, "Disable WAN Interface on CARP Backup"][spali] (gist and its comments)
- [toreamun, os-carp-vip-dhcp: single-IP WAN CARP][toreamun]
- [OPNsense forum, "CARP with DHCP on WAN"](https://forum.opnsense.org/index.php?topic=20972.15)
- [NethSecurity `ns-ha`][nethsec]
- [VyOS high availability][vyos-ha] and [conntrack sync][vyos-ct]
- [ISC, Kea HA strategies comparison][isc-ha]
- [J. Whitham, VRRP for router redundancy with keepalived][jwhitham]
- [NixOS wiki, Keepalived][nixos-wiki]

[spali]: https://gist.github.com/spali/2da4f23e488219504b2ada12ac59a7dc
[toreamun]: https://github.com/toreamun/opnsense-plugins/blob/main/net/os-carp-vip-dhcp/docs/single-ip-wan-carp.md
[nethsec]: https://dev.nethsecurity.org/packages/ns-ha/
[vyos-ha]: https://docs.vyos.io/en/latest/configuration/highavailability/
[vyos-ct]: https://docs.vyos.io/en/rolling/configuration/service/conntrack-sync.html
[isc-ha]: https://kb.isc.org/docs/kea-ha-strategies-comparison
[jwhitham]: https://www.jwhitham.org/2024/04/vrrp-router-keepalived.html
[nixos-wiki]: https://wiki.nixos.org/wiki/Keepalived
