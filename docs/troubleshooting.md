# Troubleshooting

Common failure modes when using `nix-router-optimized`.

For a structured post-change validation pass, start with
[`router-security-validation.md`](./router-security-validation.md) before
drilling into one symptom at a time.

For degraded-mode status when the dashboard is unavailable or misleading, use
[`router-degraded-status-boundary.md`](./router-degraded-status-boundary.md)
and prefer `router-diag show interfaces|firewall|vpn|health` before inventing a
second status UI path.

## Public service works from cellular but not from LAN

Symptom:
- `https://service.example.com` works off-LAN
- the same URL hangs or times out from Wi-Fi/LAN clients

Common causes:
- split DNS points the service domain at the router, but the router firewall does not allow the needed TCP port on trusted interfaces
- clients bypass local DNS and need hairpin NAT as a fallback

Checks:

```sh
nft list ruleset | rg 'dport \{ 80, 443 \}|masquerade'
getent hosts service.example.com
curl -Ik https://service.example.com/
```

Recommended fix:
- allow router-hosted service ports on trusted interfaces with `services.router-firewall.trustedTcpPorts`
- enable `services.router-firewall.hairpinNat.enable = true` as a fallback for clients using public DNS

Example:

```nix
services.router-firewall = {
  enable = true;
  trustedTcpPorts = [ 80 443 ];
  hairpinNat.enable = true;
};
```

## Reverse proxy returns `502`

Symptom:
- Caddy or another reverse proxy returns `502`
- backend service may still be running

Checks:

```sh
journalctl -u caddy -n 100 --no-pager
curl -Ik http://backend-ip:port/
systemctl status <backend-proxy-unit>
```

Typical causes:
- backend service bound only inside a container network
- host-side proxy started before the container received an IP
- router firewall allows WAN but not trusted LAN access

## PPPoE does not come up

Checks:

```sh
systemctl status pppd-<ifname>.service --no-pager
journalctl -u pppd-<ifname>.service -b --no-pager
ip addr show dev ppp0
ip route
```

Common causes:
- wrong credentials file format
- physical WAN device still managed directly by `router-networking`
- ISP requires VLAN tagging upstream of PPPoE

## IPv6 prefix delegation does not reach downstream networks

Checks:

```sh
networkctl status <wan-iface>
networkctl status <lan-iface>
ip -6 addr
ip -6 route
```

Common causes:
- upstream ISP does not provide DHCPv6-PD
- routed interface is missing RA settings
- downstream clients only have link-local IPv6 because no default route was advertised

## Technitium sync services report success but nothing changed

Symptom:
- `technitium-sync-static-hosts`, `technitium-sync-blocklists` or
  `technitium-enable-rfc2136` show `active (exited)`
- records, block lists (`blockListUrls: null`) or RFC2136 settings are missing
  in Technitium

Checks:

```sh
systemctl status technitium-bootstrap-api-token technitium-sync-static-hosts technitium-sync-blocklists --no-pager
journalctl -u technitium-sync-blocklists -b --no-pager
set -o pipefail
API_TOKEN_FILE=/var/lib/private/technitium-dns-server/nix-router-api-token
technitium_api() {
  {
    printf 'Authorization: Bearer '
    sudo cat "$API_TOKEN_FILE" | tr -d '\r\n'
    printf '\n'
  } | curl -fsS -H @- "$1"
}
technitium_api "http://127.0.0.1:5380/api/settings/get" | jq '{status, blockListUrls: .response.blockListUrls}'
```

Common causes:
- the unit used a stale token. Technitium answers `invalid-token` with HTTP 200,
  so scripts that only check `curl -f` report success. Current units check the
  JSON status, but consumer-side scripts may not.
- `apiKeySecretName` points at an age secret holding a token Technitium no
  longer accepts, and no `bootstrapPasswordSecretName` is configured to mint a
  new one.
- Technitium was not ready yet. `technitium-sync-blocklists` retries every 60s.

See [`router-technitium-automation.md`](./router-technitium-automation.md) for
the recommended token setup and verification commands.

## A removed host still resolves

Symptom:
- a host was removed from `staticHosts`, but its name still resolves

Checks:

```sh
journalctl -u technitium-sync-static-hosts -b --no-pager | grep -i stale
sudo jq length /var/lib/technitium-sync-static-hosts/managed-records.json
```

Common causes:
- the host was removed before the pruning version was deployed. The first run
  has no state file, so it prunes nothing. Delete the record once by hand.
- the record was changed by hand (different IP or CNAME target), so pruning
  leaves it alone on purpose.

## EveBox shows no events

Checks:

```sh
systemctl is-active suricata router-evebox
sudo ls -la /var/log/suricata/
grep -A3 '^outputs:' "$(systemctl cat suricata | grep -o '/nix/store/[^ ]*suricata.yaml' | head -1)"
```

Common causes:
- the Suricata config has no `outputs:` section, so nothing is written. Use
  `services.router-network-security.suricata.eveLog` (default on) or set
  `extraSettings.outputs` yourself.
- EveBox tails a different file from the one Suricata writes. Leave
  `evebox.inputFile` at its default (`eveLog.file`).

## Dashboard shows services offline

Checks:

```sh
systemctl status router-dashboard --no-pager
journalctl -u router-dashboard -b --no-pager
curl -fsS http://127.0.0.1:8888/api/status
```

Common causes:
- dashboard assumptions do not match enabled modules
- service names are present in the UI but not actually enabled on the host
- capability-restricted operations such as ping are unavailable in the current environment

## Monitoring works but data is missing or sparse

Checks:

```sh
systemctl status prometheus grafana --no-pager
curl -fsS http://127.0.0.1:9090/api/v1/targets | jq .
curl -fsS http://127.0.0.1:3001/api/health
```

Common causes:
- expected interfaces are not included in monitoring interface selection
- state directories are on the wrong filesystem or not writable
- dashboards assume node exporter metrics that are not present yet
