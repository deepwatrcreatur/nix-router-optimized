# `routerctl`

`routerctl` (also installed as `router-diag`) is the router's operational
CLI, packaged as `packages.<system>.routerctl` and in `pkgs/router-diag`.
Every subcommand takes `--json`.

| Command | Shows |
|---|---|
| `routerctl status` | Hostname, uptime, interfaces, health, VPN and firewall summary |
| `routerctl health` | The `health-*` units, nftables and systemd-networkd |
| `routerctl interfaces` | Addresses, operstate and NIC offload profiles |
| `routerctl diagnostics` | Kernel sysctls and conntrack usage |
| `routerctl firewall summary\|explain\|trace` | nftables counters, zone policy for a flow, live nftrace |
| `routerctl ha` | VRRP role, WAN health pin, Kea HA state |
| `routerctl leases` | Current Kea DHCPv4 leases |
| `routerctl dns` | Technitium zones: type, serial and sync state |
| `routerctl routes` | Kernel main-table routes and the FRR RIB |

Run the last four as root: they read `/run/kea/dhcp4.sock` and the
Technitium API token.

## JSON contract for `ha`, `leases`, `dns` and `routes`

Each output has a top-level `schema_version` (currently `1`), which changes
only on incompatible changes. Every section has `available` and `reason`.
A service that is not configured or not running gives
`"available": false` with a reason; it is not an error, and the exit code
stays 0. Scripts should check `available` before reading the other fields.

No output contains the Technitium API token or keepalived's configuration
(which holds the VRRP password).

### `routerctl ha --json`

```json
{
  "schema_version": 1,
  "vrrp": {
    "available": true,
    "reason": null,
    "role": "master",
    "role_since": 1795200000,
    "keepalived_active": true,
    "wan_health_pinned": false
  },
  "kea_ha": {
    "available": true,
    "reason": null,
    "state": "load-balancing",
    "scopes": ["router1"],
    "unsent_update_count": 0
  }
}
```

- `vrrp.role` comes from `/run/router-ha/role` (`master`, `backup` or
  `fault`), and `role_since` is when it last changed (Unix time). A stopped
  keepalived leaves `backup` there (its stop hook demotes the node), so
  check `keepalived_active` as well.
- `wan_health_pinned` is true after `router-ha.wan.healthCheck` made this
  node yield; see
  [router-ha-pair-guide.md](./router-ha-pair-guide.md#wan-health-tracking-wanhealthcheck).
- `kea_ha` comes from Kea's `ha-heartbeat` and is unavailable when
  `router-kea.dhcp4.ha` is off.

### `routerctl leases --json`

```json
{
  "schema_version": 1,
  "available": true,
  "reason": null,
  "source": "control-socket",
  "leases": [
    {"address": "10.0.10.100", "hwaddr": "02:00:00:00:10:01",
     "hostname": null, "subnet_id": 1, "expires": 1795203600}
  ]
}
```

DHCPv4 only; there is no DHCPv6 server module. `source` is
`control-socket` when Kea's `lease_cmds` hook is loaded (router-kea loads it
with `dhcp4.ha`). Otherwise it is `memfile`: the leases are read from
`/var/lib/kea/dhcp4.leases`, keeping only unexpired leases in the default
state. Leases past their expiry are left out from either source.

### `routerctl dns --json`

```json
{
  "schema_version": 1,
  "available": true,
  "reason": null,
  "zones": [
    {"name": "home.arpa", "type": "Primary", "disabled": false,
     "soa_serial": 12, "sync_failed": false, "notify_failed": false,
     "expired": false}
  ]
}
```

The token comes from the router-technitium bootstrap token, or from
`TECHNITIUM_API_KEY_FILE` (set for login shells when `apiKeySecretName` is
used). Internal zones are left out. Under `zoneReplication.ha`, the VRRP master
shows a zone as `Primary` and the standby as `Secondary`. A Technitium API
error (it returns HTTP 200 with `"status": "error"`) is reported as
unavailable with the API's message.

### `routerctl routes --json`

```json
{
  "schema_version": 1,
  "kernel": {"available": true, "reason": null, "ipv4": [], "ipv6": []},
  "frr": {"available": false, "reason": "frr is not running (FRR not enabled or stopped)"}
}
```

`kernel.ipv4` and `kernel.ipv6` are `ip -j route show table main` as is;
`frr.ipv4` and `frr.ipv6` are `vtysh -c "show ip[v6] route json"` as is. Both
use their tools' own field names.

## Tests

`vm-router-kea-ha` asserts the `ha` and `leases` shapes (Kea in
`partner-down`, every client lease listed), plus `dns`, `routes` and `vrrp`
reporting unavailable. It also checks that the stopped primary reports Kea
as unavailable. `vm-router-technitium-zone-ha` asserts the VRRP role,
Primary/Secondary zone types on each node, `leases` unavailable, and that
no output contains the API token.
