# Router Dashboard Documentation

This directory contains planning, research, and implementation status documents for the NixOS router dashboard.

## Quick Start for Agents

If you're an AI agent picking up this work, start here:

### Current State
- **Enhanced dashboard**: Modular widget-based dashboard with Chart.js graphs and GridStack layout persistence
- **Location**: `modules/router-dashboard/` (HTML, CSS, JS, API)
- **Module**: `modules/router-dashboard.nix`
- **Gateway config**: `../unified-nix-configuration/hosts/nixos/gateway/`

### What's Implemented
1. Real-time traffic graphs (Chart.js) ✅
2. CPU/Memory/Disk gauges ✅
3. Interface cards with sparklines ✅
4. Connection tracking display ✅
5. Services status table ✅
6. Quick links widget ✅
7. Speed test widget ✅
8. Wake-on-LAN widget ✅
9. Live firewall logging (SSE) ✅
10. Drag-and-drop layout persistence ✅

### Remaining Gaps
- Phase 3 service control is still deferred
- Phase 4 nftables hit counters/flowtable detail remain partial
- Historical metrics via Prometheus are not integrated yet

### Key Documents

| Document | Purpose |
|----------|---------|
| [IMPLEMENTATION-STATUS.md](./IMPLEMENTATION-STATUS.md) | **Start here** - Current implementation status |
| [DASHBOARD-ENHANCEMENT-PLAN.md](./DASHBOARD-ENHANCEMENT-PLAN.md) | Master plan with phases and priorities |
| [OPNSENSE-RESEARCH.md](./OPNSENSE-RESEARCH.md) | OPNsense dashboard analysis |
| [DASHBOARD-ARCHITECTURE.md](./DASHBOARD-ARCHITECTURE.md) | Technical implementation details |
| [CURRENT-STATE.md](./CURRENT-STATE.md) | Analysis of original dashboard (historical) |
| [module-authoring.md](./module-authoring.md) | How to add router-oriented NixOS modules to this flake |

### Implementation Phases

1. **Phase 1** (Priority): Traffic graphs, CPU/Memory gauges
2. **Phase 2**: Gateway monitoring, connection tracking
3. **Phase 3**: Services panel, DNS integration
4. **Phase 4**: Firewall stats, security widgets
5. **Phase 5**: Live logging, speed test, WoL

### Tech Stack
- **Charts**: Chart.js
- **Layout**: GridStack (drag-and-drop)
- **Backend**: Python HTTP server
- **Data**: /proc, /sys, systemctl, conntrack, nftables

### Implementation Structure

```
modules/
  router-dashboard.nix           # NixOS module (enhanced)
  router-dashboard/
    index.html                   # Main dashboard HTML
    css/dashboard.css            # Dark theme styles
    js/main.js                   # Dashboard initialization
    js/widgets/
      base-widget.js             # Widget base class
      traffic-widget.js          # Traffic graph (Chart.js)
      system-widget.js           # CPU/Memory gauges
      interface-widget.js        # Interface cards + sparklines
      connections-widget.js      # Connection tracking
      services-widget.js         # Systemd services table
      links-widget.js            # Quick links
    api/server.py                # Python HTTP + REST API
```

### Testing

The gateway host is at `gateway.deepwatercreature.com` or `10.10.10.1`.
Dashboard currently accessible at `http://gateway:8888`.

### Related Files in Gateway Config

```
unified-nix-configuration/hosts/nixos/gateway/
  router-dashboard.nix          # Current dashboard config
  scripts/network-status.sh     # Current API script
  scripts/router-api-server.py  # Current Python server
  dashboards/network-monitor.json  # Grafana dashboard
```

## Design Principles

1. **NixOS Philosophy**: Config is declarative, dashboard is read-only by default
2. **Minimal Dependencies**: Chart.js, GridStack, vanilla JS
3. **Security**: LAN-only by default, no auth assumed on trusted network
4. **Performance**: Lightweight, works on low-power router hardware
5. **Modularity**: Independent widgets that can be enabled/disabled

## References

- [OPNsense Dashboard Docs](https://docs.opnsense.org/manual/dashboard.html)
- [OPNsense Widget Development](https://docs.opnsense.org/development/frontend/dashboard.html)
- [Chart.js Documentation](https://www.chartjs.org/docs/)
- [GridStack Documentation](https://gridstackjs.com/docs/)
