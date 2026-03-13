# Router Dashboard Enhancement Plan

## Overview

This document outlines the plan to enhance the NixOS router dashboard, taking inspiration from OPNsense and pfSense web interfaces. The goal is to create a modern, feature-rich dashboard that is primarily read-only (reflecting NixOS's declarative nature) but allows some runtime adjustments where appropriate.

## Current State

### Existing Dashboard (`router-dashboard.nix`)
- Basic HTML dashboard served on port 8888
- Shows interface status (WAN/LAN/Management)
- Displays bandwidth stats (RX/TX totals and speeds)
- Connection tracking count
- System uptime
- Links to external tools (Netdata, Grafana, DNS, etc.)

### Supporting Infrastructure
- **Prometheus** on port 9090 with node exporter
- **Grafana** on port 3001 with basic network monitoring dashboard
- **Netdata** on port 8080 for real-time system monitoring
- **vnStat** for traffic statistics

### Current Limitations
1. No real-time graphs (only text values)
2. No CPU/Memory usage display on main dashboard
3. No service status monitoring
4. No firewall/nftables statistics
5. No gateway health monitoring
6. No DHCP lease information
7. No DNS statistics integration (Technitium)
8. Limited styling and responsiveness

## Proposed Enhancements

### Phase 1: Core Dashboard Improvements

#### 1.1 Real-Time Traffic Graphs
- Add Chart.js for visualization
- Live bandwidth graphs per interface (WAN, LAN, Management)
- Historical traffic views (5m, 1h, 24h, 7d)
- Sparkline mini-graphs in interface cards

#### 1.2 System Resource Widgets
- **CPU Usage**: Gauge widget with per-core breakdown
- **Memory Usage**: Gauge widget with used/total/cached
- **Disk Usage**: Bar chart for root filesystem
- **Load Average**: 1m, 5m, 15m display
- **Temperature**: If sensors available

#### 1.3 Modular Widget System
- GridStack-based layout for drag-and-drop arrangement
- User-configurable dashboard (stored in localStorage)
- Widget resize/minimize/close capabilities

### Phase 2: Network Monitoring

#### 2.1 Gateway Status Widget
- Multi-WAN health monitoring
- Latency graphs per gateway
- Packet loss indicators
- Failover status

#### 2.2 Interface Statistics
- Packets per second (PPS) graphs
- Error/drop counters
- MTU and link speed display
- MAC address display

#### 2.3 Connection Tracking
- Active connections table (top N)
- Connection states breakdown (ESTABLISHED, TIME_WAIT, etc.)
- NAT table statistics
- Per-IP connection counts

### Phase 3: Service Integration

#### 3.1 Services Status Panel
- List of systemd services with status
- Start/Stop/Restart controls (where safe)
- Service health indicators
- Journal log snippets

#### 3.2 DNS Statistics (Technitium Integration)
- Query counts
- Cache hit rates
- Top queried domains
- Block statistics (if using filtering)

#### 3.3 DHCP Information
- Active leases table
- Lease pool utilization
- Recent lease activity

### Phase 4: Firewall & Security

#### 4.1 nftables Statistics
- Rule hit counters
- Flowtable offload statistics
- Connection tracking efficiency
- Top blocked IPs/ports

#### 4.2 Fail2ban Integration
- Currently banned IPs
- Ban history
- Jail status

#### 4.3 Security Alerts Widget
- Auth failures
- Port scan attempts
- Unusual traffic patterns

### Phase 5: Advanced Features

#### 5.1 Live Logging
- Real-time firewall log stream (SSE)
- Filterable by interface/protocol/action
- Color-coded by severity

#### 5.2 Speed Test Integration
- On-demand speed test capability
- Historical results graph

#### 5.3 Wake-on-LAN
- Device list with MAC addresses
- WoL trigger buttons

## Technical Architecture

### Frontend Stack
- **Chart.js** - Charting library (OPNsense standard)
- **GridStack** - Dashboard grid layout
- **Vanilla JS** - Keep dependencies minimal
- **CSS Variables** - Theming support

### Backend API Structure
Following OPNsense's RESTful pattern:
```
/api/system/status      - System info, uptime, resources
/api/interfaces/stats   - Interface statistics
/api/traffic/live       - SSE endpoint for real-time data
/api/connections/list   - Connection tracking data
/api/services/status    - Systemd service status
/api/firewall/stats     - nftables statistics
/api/dns/stats          - Technitium API proxy
```

### Data Flow
1. Python HTTP server handles static files and API routing
2. API endpoints execute shell scripts or query Prometheus
3. Real-time data via Server-Sent Events (SSE)
4. Caching layer for expensive queries

## Implementation Priority

### Must Have (Phase 1)
- [ ] Traffic graphs with Chart.js
- [ ] CPU/Memory gauges
- [ ] Improved interface cards with sparklines
- [ ] Better API structure

### Should Have (Phase 2-3)
- [ ] Gateway monitoring
- [ ] Connection tracking table
- [ ] Services status panel
- [ ] GridStack layout

### Nice to Have (Phase 4-5)
- [ ] Live firewall logging
- [ ] DNS statistics
- [ ] Fail2ban integration
- [ ] WoL functionality

## File Structure (Proposed)

```
modules/
  router-dashboard.nix        # Main module (enhanced)
  router-dashboard/
    dashboard.html            # Main dashboard HTML
    css/
      dashboard.css           # Styles
      themes/
        dark.css              # Dark theme (default)
        light.css             # Light theme
    js/
      main.js                 # Dashboard initialization
      widgets/
        base-widget.js        # Base widget class
        traffic-graph.js      # Traffic visualization
        system-gauge.js       # CPU/Memory gauges
        interfaces.js         # Interface cards
        connections.js        # Connection tracking
        services.js           # Service status
      lib/
        chart.min.js          # Chart.js
        gridstack.min.js      # GridStack
    api/
      server.py               # Enhanced API server
      endpoints/
        system.py             # System info endpoints
        interfaces.py         # Interface endpoints
        traffic.py            # Traffic/SSE endpoints
        services.py           # Service control
```

## NixOS Integration

### Module Options (Proposed)
```nix
services.router-dashboard = {
  enable = true;
  port = 8888;
  bind-address = "10.10.10.1";

  # New options
  theme = "dark";  # "dark" | "light"
  refreshInterval = 5;  # seconds

  widgets = {
    traffic-graph.enable = true;
    system-gauge.enable = true;
    connections.enable = true;
    services = {
      enable = true;
      allowControl = false;  # Allow start/stop/restart
    };
  };

  # Integration with other services
  integrations = {
    technitium = {
      enable = true;
      apiUrl = "http://localhost:5380/api";
    };
    prometheus = {
      enable = true;
      url = "http://localhost:9090";
    };
  };
};
```

## Reference Implementations

- **OPNsense**: See `docs/OPNSENSE-RESEARCH.md`
- **pfSense**: Similar architecture, PHP-based
- **OpenWrt LuCI**: Lua-based, good mobile responsiveness
- **Ubiquiti UniFi**: Polished UI, good UX patterns

## Next Steps for Implementation

1. Review this plan and adjust priorities
2. Start with Phase 1: Add Chart.js and traffic graphs
3. Refactor API to be more modular
4. Implement system resource widgets
5. Add GridStack for layout flexibility
6. Iterate through remaining phases

## Related Documents

- `docs/OPNSENSE-RESEARCH.md` - Detailed OPNsense dashboard analysis
- `docs/DASHBOARD-ARCHITECTURE.md` - Technical implementation details
- `docs/API-SPECIFICATION.md` - API endpoint documentation (to be created)
