# Technitium Automation: Tokens, Sync Units, and Verification

Several modules in this flake change Technitium DNS Server through its HTTP API
at activation time: static host records, block lists, RFC2136/DDNS settings,
listeners, DNSSEC, NTP options, and the dashboard's DNS widgets. They all need
an API token. This page explains where that token comes from, which units use
it, and how to check that the units actually did something.

## Recommended setup: let the module mint the token

Give the module the Technitium admin password as an age secret and let
`technitium-bootstrap-api-token` create and maintain the automation token:

```nix
age.secrets.technitium-admin-password = {
  file = ./secrets/technitium-admin-password.age;
  mode = "0400";
};

services.router-technitium = {
  enable = true;
  bootstrapPasswordSecretName = "technitium-admin-password";
};

# No separately managed API key: everything uses the bootstrapped token.
# If you use router-dns-service, set it there; router-dns-service passes it
# through to router-technitium.
services.router-dns-service.technitium.apiKeySecretName = null;
# Without router-dns-service:
# services.router-technitium.apiKeySecretName = null;
```

On every start, `technitium-bootstrap-api-token`:

1. keeps the existing token at
   `/var/lib/private/technitium-dns-server/nix-router-api-token` if Technitium
   still accepts it;
2. otherwise tries the `apiKeySecretName` secret, if one is configured and valid;
3. otherwise logs in as `bootstrapUsername` (default `admin`) and mints a new
   token named `nix-router-<hostname>`.

### Why not just a `technitium-api-key` secret?

`apiKeySecretName` defaults to `"technitium-api-key"` for backwards
compatibility. A hand-made API token kept in an age secret goes stale silently
if the token is deleted in the Technitium UI, Technitium's data directory is
reset, or the router is rebuilt from scratch. Nothing re-mints it. The
bootstrap path recovers on its own.

If you keep the age secret, keep the bootstrap password too, and make the
secret readable only by root (`mode = "0400"`), not `0444`.

## Which unit uses which token

| Unit | Purpose | Token source (first that exists) |
| --- | --- | --- |
| `technitium-bootstrap-api-token` | mint/validate the automation token | admin password secret |
| `technitium-sync-static-hosts` | `services.router.dnsZone(s)` records | bootstrapped token when the bootstrap service is configured (no fallback); otherwise the `apiKeySecretName` secret |
| `technitium-sync-blocklists` | `services.router.dnsBlockLists` | bootstrapped token, else `apiKeySecretName` secret |
| `technitium-enable-rfc2136` | `services.router-technitium.rfc2136` | bootstrapped token, else `apiKeySecretName` secret |
| `technitium-zone-replication` | `services.router-technitium.zoneReplication` | bootstrapped token, else `apiKeySecretName` secret |
| `router-dashboard-technitium-token` (timer) | copies the bootstrapped token to `/run/router-dashboard/` for the dashboard | bootstrapped token |

The bootstrapped token lives under `/var/lib/private/` because Technitium runs
with `DynamicUser`. Services that are not root cannot read it there. That is
why the dashboard gets its own 0640 copy under `/run/router-dashboard/`. Do not
add `/var/lib/private/...` to another service's `ReadOnlyPaths` and expect it to
work.

## Gotcha: Technitium reports errors with HTTP 200

Technitium returns HTTP 200 even when a call fails, for example:

```json
{"status":"invalid-token","errorMessage":"Invalid token or session expired."}
```

`curl -f` therefore succeeds, and a script that only checks curl's exit code
reports success while changing nothing. This is how a stale token once left a
production router with block lists declared but never applied, and RFC2136
settings that were never re-applied.

The units in this flake check the JSON status: `technitium-sync-blocklists`
and `technitium-enable-rfc2136` require `"ok"`, and
`technitium-sync-static-hosts` fails on `"error"` or `"invalid-token"`. If you write your own
Technitium automation in a consumer flake, do the same. Better, use the
module option that already exists: for example, use
`services.router-technitium.rfc2136` instead of a hand-written
`technitium-enable-rfc2136` unit.

## Verifying that automation actually applied

The units are `oneshot` with `RemainAfterExit`, so "active (exited)" only means
the script exited 0. Check the result in Technitium itself:

```sh
TOKEN=$(sudo cat /var/lib/private/technitium-dns-server/nix-router-api-token)

# Token accepted?
curl -fsS "http://127.0.0.1:5380/api/settings/get?token=$TOKEN" | jq -r .status   # expect "ok"

# Block lists configured and loaded?
curl -fsS "http://127.0.0.1:5380/api/settings/get?token=$TOKEN" | jq '.response.blockListUrls'
curl -fsS "http://127.0.0.1:5380/api/dashboard/stats/get?token=$TOKEN&type=LastHour" \
  | jq '.response.stats | {blockListZones, totalBlocked}'

# A static host present?
curl -fsS "http://127.0.0.1:5380/api/zones/records/get?token=$TOKEN" \
  --data-urlencode zone=example.com --data-urlencode domain=host.example.com | jq '.response.records'

# RFC2136 settings
curl -fsS "http://127.0.0.1:5380/api/zones/options/get?token=$TOKEN&zone=example.com" \
  | jq '.response | {update, updateNetworkACL}'
```

`blockListZones` is the number of blocked domains loaded. It stays at 0 for a
few minutes after the first sync while Technitium downloads the lists.

## Replicating a zone to a standby router

A standby router answers nothing for a zone that lives only in the primary's
runtime state, such as one Kea DDNS fills. `zoneReplication` makes the standby
a TSIG-authenticated secondary of that zone:

```nix
# Primary (10.10.10.1)
services.router-technitium.zoneReplication = {
  tsigKeyFile = config.age.secrets.technitium-zone-transfer.path;
  primary = {
    zones = [ { name = "home.example"; } { name = "10.10.in-addr.arpa"; } ];
    secondaries = [ "10.10.10.4" ];
  };
};

# Standby (10.10.10.4)
services.router-technitium.zoneReplication = {
  tsigKeyFile = config.age.secrets.technitium-zone-transfer.path;
  secondary = {
    zones = [ { name = "home.example"; } { name = "10.10.in-addr.arpa"; } ];
    primaryAddresses = [ "10.10.10.1" ];
  };
};
```

Both sides must hold the same base64 secret
(`openssl rand -base64 32`). The primary allows AXFR/IXFR only from the listed
secondaries with that key and sends them NOTIFY on every change.

- **The unit never demotes a zone.** If the standby promoted its copy to
  Primary during a failover, activation leaves it alone. Converting it back
  to a secondary is a manual (or failover-script) step.
- **Removed secondaries are pruned.** The unit records the secondaries it
  created in `/var/lib/technitium-zone-replication/owned-secondaries` and
  deletes one that leaves the configuration, if it is still Secondary.
- **TSIG keys share one list.** Technitium's `settings/set` replaces the whole
  key list, so the RFC2136 and replication units each register every key the
  module manages. Key names must differ.
- **Secondaries are read-only.** RFC2136 updates sent to a standby fail until
  its zone is promoted.

Verify on the standby:

```sh
curl -s "http://127.0.0.1:5380/api/zones/list?token=$TOKEN" | jq '.response.zones[] | {name,type,lastRefreshed,syncFailed}'
dig @127.0.0.1 router.home.example +short
```

## Static host records and pruning

`technitium-sync-static-hosts` creates an `A` record per `staticHosts` entry and
a `CNAME` per alias. It also removes records it created earlier that are no
longer configured:

- After each successful run it writes the records it manages to
  `/var/lib/technitium-sync-static-hosts/managed-records.json`.
- On the next run, a record in that file that has left the configuration is
  deleted, but only if the live record still has the same type and value.
  Records created by DHCP/DDNS, and managed records edited by hand since, are
  left alone.
- Declaring a name takes it over. Records are added with `overwrite=true`, so
  an existing record at a configured name (hand-made or from DHCP) is replaced
  by the configured one, recorded as managed, and deleted when the name later
  leaves the config.
- Matching is by name, type and value, not by record identity. If you delete a
  managed record and recreate an identical one by hand, the service still
  treats it as its own and removes it when the host leaves the config. To keep
  a hand-made record, give it a value the config never managed.
- Failed lookups or deletions stay in the file and are retried on the next run.

Two consequences for operators:

- **The first run after upgrading prunes nothing**, because there is no state
  file yet. Records for hosts removed before the upgrade must be deleted once
  by hand (Technitium UI, or `api/zones/records/delete`).
- **Removing a host from the config now removes its DNS record** on the next
  rebuild. Before this, retired hosts kept resolving indefinitely.

Do not define the same name both as a host alias and in the zone `aliases`
attrset. It works, but it is easy to forget one copy when removing it.
