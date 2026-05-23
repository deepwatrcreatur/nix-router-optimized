# Implementation Status

Last updated: 2026-05-20

## Experimental Router Modules

### `router-clat` - FIRST SLICE ONLY

`router-clat` now exists in the exported module set, but it should not be read
as a fully mature transition feature.

Current state:

- declarative option surface exists under `services.router-clat`
- assertion coverage exists for listen/upstream topology and NAT64 overlap
- optional `router-firewall` hooks exist for the bounded CLAT path
- enable-time warnings now call out the experimental and non-HA boundary
- a non-default Elixir preview path now exists behind an explicit selector

What it does **not** yet claim:

- a complete runtime translation backend story
- mature operator guidance for broad deployment
- HA/active-owner failover support
- stable final naming beyond the current provisional `router-clat` label
- a separate extracted release boundary for the Elixir path

For the actual design and boundary, see:

- [`DECLARATIVE_CLAT.md`](./DECLARATIVE_CLAT.md)
- [`router-clat-control-plane-contract.md`](./router-clat-control-plane-contract.md)
- [`router-clat-preservation-plan.md`](./router-clat-preservation-plan.md)
- [`router-clat-elixir-extraction-decision.md`](./router-clat-elixir-extraction-decision.md)

## Phase 1: Core Dashboard - COMPLETE

### Implemented Components

#### Frontend (JavaScript/HTML/CSS)

| File | Status | Description |
|------|--------|-------------|
| `index.html` | ✅ Complete | Main dashboard HTML with widget containers |
| `css/dashboard.css` | ✅ Complete | Dark theme styles, responsive grid |
| `js/main.js` | ✅ Complete | Dashboard initialization and widget management |
| `js/widgets/base-widget.js` | ✅ Complete | Base class for all widgets |
| `js/widgets/traffic-widget.js` | ✅ Complete | Real-time traffic graph with Chart.js |
| `js/widgets/system-widget.js` | ✅ Complete | CPU/Memory/Disk gauges |
| `js/widgets/interface-widget.js` | ✅ Complete | Interface cards with sparklines |
| `js/widgets/connections-widget.js` | ✅ Complete | Connection tracking display |
| `js/widgets/services-widget.js` | ✅ Complete | Systemd services status table |
| `js/widgets/links-widget.js` | ✅ Complete | Quick links to other services |

#### Backend (Python API)

| Endpoint | Status | Description |
|----------|--------|-------------|
| `/api/system/status` | ✅ Complete | Hostname, uptime, kernel version |
| `/api/system/resources` | ✅ Complete | CPU, memory, disk, load average |
| `/api/interfaces/stats` | ✅ Complete | Interface stats with rate calculation |
| `/api/connections/summary` | ✅ Complete | Conntrack counts by protocol |
| `/api/services/status` | ✅ Complete | Systemd service states |
| `/api/firewall/stats` | ✅ Complete | nftables rule count, flowtable status |

#### NixOS Module

| Feature | Status |
|---------|--------|
| Basic enable/port/bind | ✅ Complete |
| Interface configuration | ✅ Complete |
| Quick links configuration | ✅ Complete |
| Services monitoring list | ✅ Complete |
| Refresh interval option | ✅ Complete |
| Theme option (dark/light) | ✅ Complete |
| Security hardening | ✅ Complete |

### Features Delivered

1. **Traffic Graphs**
   - Real-time bandwidth graph with Chart.js
   - Interface selector (WAN/LAN/MGMT)
   - 5-minute history (60 data points)
   - Download/Upload legend with current values

2. **System Gauges**
   - CPU usage (doughnut gauge)
   - Memory usage (doughnut gauge)
   - Disk usage (optional)
   - Load average display
   - Process count

3. **Interface Cards**
   - Per-interface status badges
   - IPv4 address display
   - Current RX/TX rates
   - Total bytes transferred
   - Sparkline mini-graphs

4. **Connections Widget**
   - Active connection count
   - Max capacity with progress bar
   - TCP/UDP breakdown

5. **Services Widget**
   - Systemd service status table
   - Active/inactive indicators
   - Summary count badge

6. **Quick Links**
   - Configurable service links
   - Emoji icons support

### File Structure

```
modules/
├── router-dashboard.nix          # NixOS module (updated)
├── router-dashboard/
│   ├── index.html                # Main dashboard
│   ├── css/
│   │   └── dashboard.css         # Styles
│   ├── js/
│   │   ├── main.js               # Dashboard init
│   │   └── widgets/
│   │       ├── base-widget.js    # Base class
│   │       ├── traffic-widget.js
│   │       ├── system-widget.js
│   │       ├── interface-widget.js
│   │       ├── connections-widget.js
│   │       ├── services-widget.js
│   │       └── links-widget.js
│   └── api/
│       └── server.py             # Python API server
```

## Phase 2: Network Monitoring - COMPLETE

### Implemented

- [x] Gateway health monitoring (latency, packet loss)
- [x] Connection tracking table (top connections with filter)
- [x] Firewall stats widget (rules count, packet counters)

### Widgets Added

1. **Gateway Health Widget**
   - Pings upstream gateway, Cloudflare (1.1.1.1), Google (8.8.8.8)
   - Shows latency in ms and packet loss %
   - Latency history graph
   - Status indicators (UP/DOWN/DEGRADED)

2. **Top Connections Widget**
   - Filterable by protocol (All/TCP/UDP)
   - Shows source/destination IPs and ports
   - Connection state for TCP
   - Timeout/age display

3. **Firewall Widget**
   - nftables rules count
   - Flowtable status (ON/OFF)
   - Total packets in/out

### API Endpoints Added

| Endpoint | Description |
|----------|-------------|
| `/api/gateway/health` | Ping latency to upstream gateways |
| `/api/connections/top` | Top N connections with filtering |
| `/api/firewall/stats` | Enhanced with packet counters |

## Phase 3: Service Integration - IN PROGRESS

### Implemented

- [x] DNS statistics (Technitium API integration)
- [x] DHCP lease information

### Planned

- [ ] Service control (start/stop/restart) - requires user authentication

### Widgets Added

1. **DNS Statistics Widget**
   - Total queries (last hour)
   - Blocked queries count and percentage
   - Cache hit rate
   - Top 5 queried domains
   - Top 5 clients

2. **DHCP Leases Widget**
   - DHCP scope overview (enabled/disabled, IP range)
   - Active lease count per scope
   - Lease table (IP, hostname, MAC, expiry)

### API Endpoints Added

| Endpoint | Description |
|----------|-------------|
| `/api/dns/stats` | Technitium DNS statistics (queries, blocked, cached, top domains/clients) |
| `/api/dhcp/leases` | DHCP scopes and active leases |

### Notes

- DNS/DHCP widgets integrate with Technitium DNS Server API
- Requires `TECHNITIUM_API_KEY_FILE` environment variable (automatically set from agenix)
- Service control intentionally deferred - requires user authentication for write operations

## Phase 4: Firewall & Security - IN PROGRESS

### Implemented

- [x] Fail2ban integration
- [x] Blocked IP display
- [x] Jail status monitoring

### Planned

- [ ] nftables rule hit counters (requires counter rules in nftables config)
- [ ] Flowtable offload statistics (requires flowtable configuration)

### Widgets Added

1. **Fail2ban Widget**
   - Active jail count
   - Currently banned IP count
   - Per-jail statistics (failed attempts, total bans)
   - Banned IP list display

### API Endpoints Added

| Endpoint | Description |
|----------|-------------|
| `/api/fail2ban/status` | Fail2ban jails, banned IPs, statistics |

### Notes

- Fail2ban widget requires sudoers rule for fail2ban-client (automatically configured)
- nftables hit counters require counter rules to be defined in nftables config
- Flowtable statistics require flowtable to be configured in the kernel

## Phase 5: Advanced Features - COMPLETE

### Implemented

- [x] Speed test integration
- [x] Wake-on-LAN
- [x] Live firewall logging (SSE)
- [x] GridStack drag-and-drop layout

### Widgets Added

1. **Speed Test Widget**
   - On-demand internet speed testing using speedtest-cli
   - Displays download/upload speeds (Mbps) and ping (ms)
   - Shows server name used for testing
   - Progress indicator during test
   - Test history stored in localStorage (last 10 tests)

2. **Wake-on-LAN Widget**
   - Configurable device list from NixOS module options
   - Sends UDP magic packets directly from the dashboard API
   - Per-device wake action with success/error feedback

3. **Firewall Log Widget**
   - Server-Sent Events (SSE) stream for live firewall activity
   - Recent log backlog on initial connect
   - Parses prefixed nftables kernel log lines into structured entries

4. **GridStack Layout**
   - Drag-and-drop and resize support for widgets
   - Layout persistence in localStorage
   - Reset layout control in the dashboard header

### API Endpoints Added

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/speedtest/run` | POST | Start a new speed test |
| `/api/speedtest/status` | GET | Get test status/results |
| `/api/wol/wake` | POST | Send a Wake-on-LAN magic packet |
| `/api/firewall/logs/recent` | GET | Return recent firewall log entries |
| `/api/firewall/logs/stream` | GET | Stream live firewall logs over SSE |

## Usage Example

```nix
{
  services.router-dashboard = {
    enable = true;
    port = 8888;
    bind-address = "10.10.10.1";

    interfaces = [
      { device = "ens17"; label = "WAN"; role = "wan"; }
      { device = "ens16"; label = "LAN"; role = "lan"; }
      { device = "ens18"; label = "Management"; role = "mgmt"; }
    ];

    links = [
      { label = "Netdata"; url = "http://gateway:8080"; icon = "📊"; }
      { label = "Grafana"; url = "http://gateway:3001"; icon = "📈"; }
    ];

    services = [
      "nftables"
      "caddy"
      "prometheus"
      "grafana"
      "netdata"
      "technitium-dns-server"
    ];

    refreshInterval = 5;
    theme = "dark";

    wakeOnLan.devices = [
      {
        name = "Media Server";
        macAddress = "AA:BB:CC:DD:EE:FF";
        broadcastAddress = "10.10.10.255";
        port = 9;
      }
    ];
  };
}
```

## Testing

To test the dashboard locally:

1. Build the flake: `nix build .#nixosConfigurations.router-example.config.system.build.toplevel`
2. Or apply to gateway: `sudo nixos-rebuild switch --flake .#gateway`
3. Access at `http://gateway:8888`

## Known Issues

1. Chart.js loaded from CDN - should be packaged locally for offline use
2. Interface mapping hardcoded in server.py - needs to use Nix config
3. No authentication - assumes trusted LAN access
4. Light theme not yet implemented (CSS variables ready)
5. Live firewall logging depends on nftables log rules with `FW-*` prefixes

## Next Steps

1. Test on actual gateway hardware
2. Add error handling for API failures
3. Consider adding Prometheus query support for historical data
