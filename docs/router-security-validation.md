# Router Security Validation Runbook

Use this runbook after router changes to confirm the **running system** still
matches the intended security posture.

This is not a module reference.
It is an operator-facing validation loop for the live router from three
viewpoints:

- router-local
- LAN-side
- WAN-side

The goal is to answer questions like:

- did a firewall or routing change leave an unexpected listener exposed?
- is a suspected outage more likely DHCP, DNS, or forwarding?
- does the WAN-facing surface still match the features that are intentionally
  enabled?

## When To Run This

Run this validation:

- after first deployment
- after firewall changes
- after DNS service changes
- after DHCP service changes
- after HA, WAN, or routing changes
- after upstream modem, bridge, or topology changes
- periodically for assurance even without a recent change

For especially risky changes, pair this with the separate apply-safety /
rollback procedure rather than treating validation as an afterthought.

## Before You Start

- know which optional features are intentionally enabled on this router
- know which interfaces are WAN-facing and which are trusted/LAN-facing
- do **not** commit scan artifacts, public IP values, or one-off incident notes
  into git
- if possible, have:
  - one router-local shell
  - one LAN client
  - and one WAN-side vantage point such as a cellular connection or external
    VPS

## 1. Router-Local Checks

Use these first to inspect what the router itself believes it is doing.

### 1.1 Check service state

```bash
systemctl --failed
systemctl status nftables --no-pager
systemctl status systemd-networkd --no-pager
systemctl status router-dashboard --no-pager
```

Then check the specific services your deployment actually uses, for example:

```bash
systemctl status unbound technitium-dns-server dnsmasq --no-pager
systemctl status kea-dhcp4-server --no-pager
systemctl status keepalived --no-pager
systemctl status frr --no-pager
systemctl status tailscaled openvpn-* wg-quick-* --no-pager
```

Stop-and-investigate findings:

- failed units in the service plane you expected to be active
- keepalived or networkd failures after HA or WAN work
- DNS or DHCP daemons down after a change that should not have touched them

### 1.2 Inspect listeners

```bash
ss -tulpen
```

Look for:

- listeners bound on WAN-reachable addresses
- listeners bound on `0.0.0.0` or `::` when LAN-only binding was expected
- newly opened ports that were not part of the intended change

Common expected-open surfaces depend on enabled features.
Examples:

- DNS: `53/tcp`, `53/udp` on LAN/trusted addresses when a DNS service is enabled
- DHCP: `67/udp` on intended DHCP-serving interfaces
- NTP: `123/udp` on trusted interfaces if `router-ntp` is enabled
- HTTPS or reverse proxy: `443/tcp` only if you intentionally expose it
- dashboard: only on the interface/binding you actually configured
- BGP: `179/tcp` only if `router-bgp` is enabled
- VRRP/Keepalived: protocol behavior is expected when HA is enabled, but that
  does not mean unrelated services should bind broadly

Stop-and-investigate findings:

- management or dashboard listeners exposed on WAN unexpectedly
- DNS or DHCP listening on interfaces outside the intended trust boundary
- duplicate or surprising service instances after HA or failover work

### 1.3 Inspect nftables policy

```bash
nft list ruleset
```

Useful focused filters:

```bash
nft list ruleset | rg 'dport|sport|vrrp|masquerade|snat|dnat|drop|reject'
```

Look for:

- the expected WAN-to-LAN default deny posture
- explicit trusted/LAN allowances that match enabled features
- NAT or hairpin rules that were intentionally configured
- VRRP, BGP, DHCP, DNS, or VPN allowances only when the corresponding feature
  exists

Stop-and-investigate findings:

- broad `accept` rules you did not mean to add
- WAN-facing port allowances with no matching intended feature
- missing trusted-interface allowances for router-hosted services that LAN users
  depend on

### 1.4 Inspect routing and policy routing

```bash
ip route
ip -6 route
ip rule
```

Use this to separate firewall problems from path problems.

Look for:

- the correct default route on the intended WAN uplink
- expected policy-routing rules if multi-WAN, VPN, or source-aware routing is
  in use
- sane IPv6 routes after prefix, NAT64, CLAT, or NDP-proxy changes

Stop-and-investigate findings:

- no default route
- default route on the wrong uplink
- missing policy-routing rules after WAN, VPN, or multi-WAN work

### 1.5 Review recent logs

```bash
journalctl -b -p warning..alert --no-pager
journalctl -u systemd-networkd -b --no-pager
journalctl -u nftables -b --no-pager
```

Then inspect service-specific logs relevant to the changed area:

```bash
journalctl -u unbound -b --no-pager
journalctl -u kea-dhcp4-server -b --no-pager
journalctl -u keepalived -b --no-pager
```

## 2. LAN-Side Checks

Use another host on the trusted/LAN side.
This is the quickest way to tell whether the router still works as a service
provider rather than only looking healthy locally.

### 2.1 Validate basic reachability

```bash
ping -c 3 <router-lan-ip>
curl -I http://<router-lan-ip>:<expected-port>
```

Interpretation:

- if the router itself is unreachable from LAN, suspect interface, bridge,
  firewall, or VLAN problems before you blame DNS
- if ping works but router-hosted services fail, suspect listener binding or
  trusted-interface firewall policy

### 2.2 Validate DNS through the router

```bash
dig @<router-lan-ip> example.com
dig @<router-lan-ip> <local-zone-name>
getent hosts example.com
```

Interpretation:

- if raw IP internet access works but DNS lookups fail, suspect the DNS service
  layer rather than generic forwarding
- if only local-zone names fail, suspect zone sync, split DNS, or resolver
  configuration rather than WAN reachability

### 2.3 Validate DHCP behavior when relevant

Use a fresh or bounced client where safe to do so.

Checks:

- does the client receive an address from the expected subnet?
- does it receive the intended DNS server?
- does it receive a default gateway?

If you have a controlled test client, compare its lease information with the
intended router subnet and DNS settings.

Interpretation:

- no lease at all suggests DHCP or LAN-path trouble
- a lease without working name resolution suggests DNS trouble
- a valid lease and DNS but no internet suggests routing, NAT, or firewall

### 2.4 Scan the LAN-facing surface

Use `nmap` from a trusted host:

```bash
nmap -sS -sU -Pn <router-lan-ip>
```

You do not need to treat "many ports closed" as a failure.
What matters is whether the **open** ports match the enabled features and trust
boundary you intended.

Expected LAN-side openings may include:

- DNS
- DHCP-related behavior
- NTP
- HTTPS/HTTP for explicitly enabled local admin or reverse proxy surfaces
- VPN ports only if intentionally LAN-reachable

Stop-and-investigate findings:

- surprise admin interfaces
- router-dashboard or reverse-proxy ports open where they should not be
- unexpected service duplication after failover work

## 3. WAN-Side Checks

Use a host that is genuinely outside the LAN path.
Cellular is often enough for a quick validation pass.

### 3.1 Confirm the intended public/WAN identity

Before broad scanning, confirm you are testing the correct public target:

```bash
curl https://ifconfig.me
```

or check the WAN IP through your preferred out-of-band method.

Do **not** commit the resulting public IP or scan output into git.

### 3.2 Scan the WAN-facing surface

From the outside vantage point:

```bash
nmap -Pn <public-ip>
```

If you intentionally expose UDP services or a specific protocol surface, use a
narrower targeted scan that matches your deployment rather than a noisy generic
one.

Interpretation:

- only the intentionally exposed WAN services should appear open
- filtered or closed is generally the expected result for everything else

Expected-open WAN surfaces vary by deployment.
Examples:

- HTTPS reverse proxy
- WireGuard UDP port
- OpenVPN port
- BGP TCP `179` only in the rare deployments that intentionally expose it
- remote-admin surfaces only when that is explicitly the design

Stop-and-investigate findings:

- dashboard or management interfaces open to the WAN unexpectedly
- DNS, DHCP, or NTP visible on the WAN when that was not intentional
- a broader exposed set than the modules and docs imply

### 3.3 Validate real user paths for intentionally exposed services

For services that are supposed to be reachable from WAN, test the real path:

```bash
curl -Ik https://service.example.com/
```

or the relevant protocol-specific client.

This distinguishes:

- service-down
- path/firewall/NAT issues
- and DNS or certificate problems

## How To Interpret Common Failure Shapes

### DHCP likely

Suspect DHCP first when:

- new clients do not get leases
- clients fall back to self-assigned or missing IPv4
- existing clients keep working for a while, but new ones fail

Router-local checks to confirm:

- `systemctl status kea-dhcp4-server`
- DHCP listener presence in `ss -tulpen`
- expected subnet/interface shape

### DNS likely

Suspect DNS first when:

- clients can ping IPs but not resolve names
- local services by IP work but domain names fail
- router-local resolver service is unhealthy

Router-local checks to confirm:

- `systemctl status unbound technitium-dns-server dnsmasq`
- `dig @<router-lan-ip> ...`

### Firewall or routing likely

Suspect firewall/routing when:

- router-local services look healthy
- but LAN clients cannot reach them or cannot reach WAN destinations
- or WAN-side exposure differs from intended policy

Router-local checks to confirm:

- `nft list ruleset`
- `ip route`
- `ip rule`

### Unexpected WAN exposure likely

Suspect exposure drift when:

- WAN-side scans show listeners that should be LAN-only
- services bind to wildcard/WAN addresses unexpectedly
- recent changes touched firewall, reverse proxy, HA, or interface assignment

## Minimal Validation Cadence

If you need a compact checklist after a risky change:

1. router-local:
   - `systemctl --failed`
   - `ss -tulpen`
   - `nft list ruleset`
   - `ip route && ip rule`
2. LAN-side:
   - test DNS through the router
   - confirm a real client can reach the internet
   - run a small `nmap` against the router LAN IP
3. WAN-side:
   - run an external scan against the public target
   - verify any intentionally exposed service path

## Related Docs

- [`router-security-hardened.md`](./router-security-hardened.md)
- [`router-ha-ownership.md`](./router-ha-ownership.md)
- [`router-dhcp-single-active.md`](./router-dhcp-single-active.md)
- [`troubleshooting.md`](./troubleshooting.md)
