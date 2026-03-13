# OPNsense Dashboard Research

This document summarizes research into OPNsense's web dashboard implementation for use as inspiration in enhancing the NixOS router dashboard.

## Dashboard Overview

OPNsense provides a widget-based dashboard with the following key components:

### Main Dashboard Widgets

**System Monitoring:**
- System Information - OPNsense version and update status
- Memory Usage - Current memory utilization
- Disk Usage - Storage capacity and usage
- CPU Usage - Processor usage metrics with graphical representation
- Gateways - Active gateways and their status

**Network & Traffic:**
- Traffic Graph - Real-time data visualization
- Interface Statistics - Packet counts, data volume, errors per interface
- Interface Status Overview - Interface information and statistics

**Services & Firewall:**
- Services Panel - Configured services with start/restart/stop controls
- Firewall Panel - Snapshot of current firewall activity with live logging
- Announcements - Latest OPNsense project news

Each widget is customizable via dashboard edit mode (resize, relocate, remove). Configuration is per-user.

## API Endpoint Structure

OPNsense uses a consistent RESTful API architecture.

### Endpoint Format
```
https://opnsense.local/api/<module>/<controller>/<command>/[<param1>/[<param2>/...]]
```

### HTTP Methods
- **GET**: Retrieving data
- **POST**: Creating, updating, or executing actions
- All requests/responses use JSON format

### Core API Categories

#### System & Diagnostics
```
/api/core/system/status           - System status information
/api/core/system/reboot           - System reboot
/api/diagnostics/activity/*       - CPU usage, memory, activity logs
/api/diagnostics/firewall/*       - Firewall state, rules, PF stats
/api/diagnostics/interface/*      - Interface stats, ARP/NDP, routes
/api/diagnostics/traffic/*        - Traffic analysis with configurable polling
```

#### Services Management
```
/api/core/service/search          - Search/list services (POST with pagination)
/api/core/service/status          - Service status
```
Returns: Service ID, locked status, running state, description, name

#### Interfaces
```
/api/interfaces/overview/interfaces_info   - Detailed interface statistics
/api/interfaces/overview/get_interface     - Specific interface data
/api/interfaces/overview/reload_interface  - Refresh interface status
```

#### Routes & Gateways
```
/api/routes/gateway/status        - Status of configured gateways
```

#### Firewall
```
/api/core/firewall/filter/search_rule  - Search firewall rules
/api/core/firewall/alias/*             - Alias manipulation
```

### Authentication
- API credentials (key/secret pair) via basic authentication
- User authorization determines accessible resources via "Effective Privileges"
- Endpoint discovery: Browser dev tools, filter `/api/`

## JavaScript Charting & UI Libraries

### Chart Library
- **Chart.js** - Primary charting library
- CSS variables with `--chart-js-` prefix for programmatic styling

### Widget Framework
- **GridStack** - Dashboard grid layout system
- Drag-and-drop widget positioning and resizing

### Base Widget Classes
```javascript
BaseWidget       // General-purpose widget base
BaseTableWidget  // Dynamic table widgets (extends BaseWidget)
BaseGaugeWidget  // Gauge/value widgets (responsive)
```

## Widget Architecture

### Widget Class Structure
```javascript
export default class WidgetName extends BaseWidget {
  // Implementation
}
```

### Required Widget Functions

#### constructor()
Runs once when widget is created. Sets defaults:
- `this.title` - Widget title in header
- `this.tickTimeout` - Update interval in seconds (default: 10)

#### getMarkup()
Returns jQuery object with static HTML structure. Called once.

#### onMarkupRendered()
Called after markup is rendered to DOM. Used for initialization.

#### onWidgetTick()
Called every tick interval. Data fetching and updates occur here:
- Calls API endpoint to retrieve data
- Maps data to HTML objects
- Appends/replaces content in widget structure

#### onWidgetClose()
Cleanup when widget closes. Called automatically unless overridden.

### Real-Time Data Streaming

For persistent connections:
```javascript
super.openEventSource(apiEndpoint, callbackFunction)
```

- Uses Server-Sent Events (SSE) for real-time delivery
- Callback receives event with `data` property
- `closeEventSource()` - Closes active connection

### Widget Configuration Files

Each widget requires two files:

#### JavaScript File (.js)
Location: `/usr/local/opnsense/www/js/widgets/`
Contains widget logic and class definition.

#### Metadata XML File (.xml)
Location: `/usr/local/opnsense/www/js/widgets/Metadata/`

```xml
<metadata>
  <widgetname>
    <filename>WidgetName.js</filename>
    <endpoints>
      <endpoint>/api/core/dashboard/product_info_feed</endpoint>
      <endpoint>/api/core/firmware/status</endpoint>
    </endpoints>
    <translations>
      <title>Widget Title</title>
    </translations>
  </widgetname>
</metadata>
```

### API Access Control
- Each widget class exposes the API endpoints it uses
- Controller applies per-widget ACL checks
- Widget unavailable if any declared endpoint is inaccessible

### Responsiveness
- Widgets receive width/height updates on resize
- `onWidgetResize(width, height, widget)` - Called on resize events
- Allows responsive layout adaptation

## Traffic Graph Implementation

### Real-Time Bandwidth
- Uses `/api/diagnostics/traffic/*` endpoints
- Configurable polling intervals
- Chart.js for visualization
- `openEventSource()` for persistent streaming
- Updates via `onWidgetTick()` at specified intervals

## System Resources Monitoring

### CPU, Memory, Disk
- Data sources: `/api/diagnostics/activity/*` endpoints
- BaseGaugeWidget for gauge representation
- CPU: per-core and total usage percentages
- Memory: used/total with visual gauge
- Disk: capacity utilization

## Services Status Panel

### Implementation
- Uses `/api/core/service/search` POST endpoint
- BaseTableWidget for dynamic table display
- Returns: name, description, status, locked state
- Actions: start/restart/stop on services

## Interface & Firewall Statistics

### Interface Status
- `/api/interfaces/overview/interfaces_info`
- Per-interface packet counts
- Data volume (bytes in/out)
- Transmission errors
- Real-time updates via periodic API calls

### Firewall/Connection Tracking
- `/api/diagnostics/firewall/*` provides state table
- Active connections with source/dest, ports, protocol
- Live firewall logging capability
- Connection state retrieval

### Gateway Monitoring
- `/api/routes/gateway/status` - Status array per gateway
- Multi-WAN setup monitoring
- Real-time health and statistics

## Key Patterns for NixOS Dashboard

1. **Modular Widget System** - Independent, self-contained widgets
2. **GridStack Layout** - Drag-and-drop dashboard grid
3. **Chart.js Visualizations** - Consistent charting
4. **Gauge Widgets** - Simple, responsive metric display
5. **Real-Time Updates** - Interval-based polling + SSE streaming
6. **ACL-Based Access** - Endpoint permissions in metadata
7. **Responsive Design** - onWidgetResize handling
8. **Minimal Dependencies** - jQuery, Chart.js, GridStack
9. **RESTful API** - `/api/module/controller/action` pattern
10. **Per-User Config** - Store layout per user

## Sources

- [OPNsense Dashboard Documentation](https://docs.opnsense.org/manual/dashboard.html)
- [OPNsense Dashboard Widgets Development](https://docs.opnsense.org/development/frontend/dashboard.html)
- [OPNsense API Reference](https://docs.opnsense.org/development/api.html)
- [OPNsense Diagnostics API](https://docs.opnsense.org/development/api/core/diagnostics.html)
- [OPNsense Firewall API](https://docs.opnsense.org/development/api/core/firewall.html)
- [OPNsense Interfaces API](https://docs.opnsense.org/development/api/core/interfaces.html)
- [OPNsense API How-To](https://docs.opnsense.org/development/how-tos/api.html)
- [Custom Widget Tutorial](https://jono-moss.github.io/post/opnsense-dashboard-widget-06-12-2024/)
- [OPNsense System Health](https://docs.opnsense.org/manual/systemhealth.html)
- [GitHub - OPNsense Core](https://github.com/opnsense/core)
