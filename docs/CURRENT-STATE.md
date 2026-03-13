# Current State Analysis

Last updated: 2026-03-12

## Existing Dashboard Implementation

### Module Location
`modules/router-dashboard.nix`

### Current Features
- Simple HTML dashboard served via Python HTTP server
- Port 8888, configurable bind address
- Interface monitoring (WAN/LAN/Management)
- Basic stats: RX/TX bytes, speeds, connection count
- Quick links to external tools (Netdata, Grafana, DNS, Proxy)
- 5-second auto-refresh via JavaScript fetch

### Current API
- Single endpoint: `/api/stats`
- Returns JSON with:
  ```json
  {
    "hostname": "...",
    "uptime": "...",
    "connections": 1234,
    "interfaces": {
      "ens17": { "device": "...", "status": "up", "rx": ..., "tx": ... }
    }
  }
  ```

### Current Dashboard HTML
- Inline styles (no external CSS)
- Dark theme with gradient background
- Card-based layout
- No charts/graphs, only text values
- No localStorage for preferences

## Gateway Configuration

### Location
`unified-nix-configuration/hosts/nixos/gateway/router-dashboard.nix`

### Supporting Services Configured
| Service | Port | Purpose |
|---------|------|---------|
| vnStat | - | Traffic statistics |
| Prometheus | 9090 | Metrics collection |
| Node Exporter | 9100 | System metrics |
| Blackbox Exporter | 9115 | Ping/latency |
| Grafana | 3001 | Dashboards |
| Netdata | 8080 | Real-time monitoring |
| Router Dashboard | 8888 | Custom dashboard |

### Prometheus Scrape Configs
- `gateway` job: localhost:9100
- `node` job: localhost:9100

### Grafana Provisioning
- Datasource: Prometheus at 10.10.10.1:9090
- Dashboard provider: `/etc/grafana-dashboards`

### Existing Grafana Dashboard
`dashboards/network-monitor.json`:
- WAN/LAN RX/TX totals (stat panels)
- WAN/LAN traffic rate graphs (timeseries)
- Active connections, CPU, Memory, Uptime (stat panels)

## Network Status Script
`scripts/network-status.sh`

### Features
- Reads from /sys/class/net for interface stats
- Calculates speeds by comparing with previous readings
- Stores state in /run/router-dashboard/
- Outputs JSON for API consumption

### Data Collected
- Interface: name, IPv4, IPv6, state, MTU
- Stats: rx/tx bytes, packets, errors, speeds

## Identified Gaps

### Missing from Dashboard
1. **No graphs** - Only text values, no visual charts
2. **No CPU/Memory** - Must go to Netdata for this
3. **No service status** - Can't see if services are running
4. **No firewall info** - nftables stats not shown
5. **No DHCP info** - No lease visibility
6. **No DNS stats** - Technitium data not integrated
7. **No gateway health** - No latency/packet loss graphs
8. **No layout customization** - Fixed layout
9. **No historical view** - Only current values

### Technical Debt
1. Inline HTML in Nix module is hard to maintain
2. No separation of concerns (HTML/CSS/JS)
3. Single monolithic API endpoint
4. No error handling in frontend
5. No caching of expensive operations

## Opportunities

### Leverage Existing Infrastructure
- Prometheus already collecting metrics - use for historical data
- Grafana already configured - can embed or link
- Netdata available - could iframe or API proxy
- Node exporter provides CPU/Memory/Network data

### Quick Wins
1. Add Chart.js for traffic sparklines
2. Query Prometheus for CPU/Memory instead of /proc
3. Add systemctl queries for service status
4. Add conntrack summary to existing API

### Integration Points
- Technitium DNS API at localhost:5380
- nftables JSON output (`nft -j list ruleset`)
- systemd dbus for service control
- Prometheus API for historical queries
