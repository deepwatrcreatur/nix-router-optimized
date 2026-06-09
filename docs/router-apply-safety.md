# Router Apply-Safety and Rollback Runbook

Use this runbook for **risky live router updates**.

The point is simple:

- `nixos-rebuild switch` is not self-validating
- generation rollback is valuable, but it is not the same thing as a safe
  acceptance procedure
- firewall, DHCP, DNS, WAN, HA, and routing changes can strand both users and
  the operator if the recovery path was not prepared before the switch

This is a manual safety procedure.
It is **not** an auto-rollback feature.

## What Counts As A Risky Change

Treat these as risky by default:

- firewall policy changes
- DNS service changes
- DHCP service changes
- WAN uplink changes
- HA / Keepalived / VIP ownership changes
- routing or policy-routing changes
- interface, bridge, VLAN, or modem-topology changes

If a change can break:

- SSH reachability
- LAN DNS
- fresh DHCP lease behavior
- or WAN connectivity

then use this procedure.

## Why This Exists

The repo already has generation rollback.
That is useful, but it answers a different question:

- **generation rollback**: how to recover to an earlier known state
- **post-change validation**: how to decide whether the new state is actually
  acceptable
- **automated rollback**: a future possible capability, not what this doc
  claims today

Do not confuse those three.

## Before The Change

Do these steps **before** running `nixos-rebuild switch`.

### 1. Identify the previous generation

Know what you will roll back to if the new config fails.

Useful checks:

```bash
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
readlink -f /run/current-system
```

You do not need to memorize the entire history.
You do need to know:

- which generation is current
- which immediately previous generation is your last-known-good candidate

### 2. Confirm your recovery path

At least one of these must be real before you proceed:

- local console
- Proxmox console
- IPMI/iDRAC/iLO or other out-of-band access
- another management path that does not depend on the exact router services you
  are about to change

If you only have an SSH session traversing the router you are about to mutate,
you do **not** have a reliable recovery path.

### 3. Identify another vantage point

Prefer to have:

- one router-local shell
- one LAN-side host
- and, for WAN-facing changes, one external/WAN-side vantage point

This matters because the router can look healthy from its own shell while still
being broken for users.

### 4. Record what you intend to preserve

Know which behaviors must still work immediately after the switch.

Minimum examples:

- SSH to the router from the intended management path
- DNS resolution through the router
- fresh DHCP lease behavior if DHCP changed
- WAN internet access from a LAN client
- expected HA ownership state if HA changed

Do not switch first and only then decide what "healthy" means.

## During The Change

### 1. Keep your current shell open

Do not replace your last good router shell with a new session before the change
has been accepted.

### 2. Apply the change

Use your normal deploy path, for example:

```bash
sudo nixos-rebuild switch
```

If your workflow uses another wrapper, the same safety logic still applies.

### 3. Do not treat a successful switch as acceptance

A completed `switch` only means:

- the new generation activated on that machine

It does **not** prove:

- LAN clients still get leases
- DNS still resolves correctly
- WAN path still works
- WAN exposure still matches intent
- or that you can reconnect once the current shell is gone

## Immediate Post-Switch Checks

Run these as soon as the change is active.

### 1. Router-local checks

Start with:

```bash
systemctl --failed
systemctl status systemd-networkd --no-pager
ip route
ip rule
```

Then inspect the changed layer directly:

```bash
systemctl status nftables --no-pager
systemctl status unbound technitium-dns-server dnsmasq --no-pager
systemctl status kea-dhcp4-server --no-pager
systemctl status keepalived --no-pager
ss -tulpen
```

### 2. LAN-side acceptance checks

From another host where possible:

- confirm SSH reachability to the router
- confirm DNS resolution through the router
- confirm WAN connectivity

Examples:

```bash
ssh <router-management-name-or-ip>
dig @<router-lan-ip> example.com
ping -c 3 1.1.1.1
curl -I https://example.com
```

Interpretation:

- SSH failure after a firewall or WAN change suggests management-path breakage
- raw IP reachability without DNS suggests DNS trouble
- no lease or missing gateway on a fresh client suggests DHCP trouble
- DNS works but internet does not suggests firewall, NAT, or routing trouble

### 3. WAN-side checks when relevant

If the change touched WAN exposure, reverse proxying, VPN ingress, or firewall
policy, test from outside:

```bash
nmap -Pn <public-ip>
curl -Ik https://service.example.com/
```

Do not commit resulting public IPs or scan artifacts into git.

## How To Tell DHCP From DNS From Routing

### DHCP is the likely failed layer when:

- fresh clients receive no lease
- clients self-assign or remain link-local
- existing clients work temporarily but new clients fail

Useful confirmation:

```bash
systemctl status kea-dhcp4-server --no-pager
ss -tulpen | rg ':67 '
```

### DNS is the likely failed layer when:

- clients can reach raw IPs but not names
- local service IPs work but hostnames fail
- the resolver daemon is unhealthy

Useful confirmation:

```bash
dig @<router-lan-ip> example.com
systemctl status unbound technitium-dns-server dnsmasq --no-pager
```

### Routing / firewall is the likely failed layer when:

- router-local services appear healthy
- but clients cannot reach the router or the internet correctly
- or WAN-side exposure no longer matches intent

Useful confirmation:

```bash
nft list ruleset
ip route
ip rule
```

## Rollback Procedure

### If the router is still reachable

Roll back immediately:

```bash
sudo nixos-rebuild switch --rollback
```

Then re-run the minimum acceptance checks:

- SSH reachability
- DNS resolution through the router
- WAN connectivity

Do not assume the rollback succeeded just because the command returned.

### If the router is not reachable but console or out-of-band access exists

Use the console path to boot or switch back to the previous generation.

The exact mechanism depends on your environment, but the logic is:

1. regain console access
2. select or activate the previous generation
3. restore the last-known-good state
4. verify management, DNS, DHCP, and WAN behavior before attempting another
   risky change

### If you have neither rollback path nor out-of-band access

Be explicit about the risk:

- an agent or operator behind the broken router may not be able to recover
  reliably
- this is why the recovery path must be prepared **before** the switch

## Minimal Safe Procedure

If you need the compact version:

1. identify the previous generation
2. confirm console / Proxmox / out-of-band recovery
3. keep one current shell open
4. identify a LAN-side validation host
5. apply the change
6. verify:
   - SSH reachability
   - DNS through the router
   - WAN connectivity
   - any changed HA or WAN behavior
7. if the checks fail, rollback immediately

## Relationship To Other Docs

- Use [`router-security-validation.md`](./router-security-validation.md) for the
  fuller router-local, LAN-side, and WAN-side validation loop.
- Use [`router-dhcp-single-active.md`](./router-dhcp-single-active.md) when the
  risky change involves the current single-active DHCP reference pair.
- Use [`router-ha-ownership.md`](./router-ha-ownership.md) to understand what
  HA does and does not promote automatically.
