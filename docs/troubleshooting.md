# Troubleshooting

Common failure modes when using `nix-router-optimized`.

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

## Technitium sync services do not populate zones or blocklists

Checks:

```sh
systemctl status router-dns-zone-sync --no-pager
systemctl status router-dns-blocklists-sync --no-pager
journalctl -u router-dns-zone-sync -b --no-pager
journalctl -u router-dns-blocklists-sync -b --no-pager
curl -fsS http://127.0.0.1:5380/api/dns/status
```

Common causes:
- API key secret missing
- Technitium not yet ready when sync service runs
- service can reach the API locally but not apply records because the payload is invalid

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
