# Dashboard Architecture

This document provides technical implementation details for the enhanced NixOS router dashboard.

## Overview

The enhanced dashboard follows a modular architecture inspired by OPNsense, adapted for NixOS's declarative philosophy.

```
┌─────────────────────────────────────────────────────────────┐
│                    Browser (Client)                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  Dashboard UI                            ││
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       ││
│  │  │ Traffic │ │   CPU   │ │ Memory  │ │Services │ ...   ││
│  │  │  Graph  │ │  Gauge  │ │  Gauge  │ │  Table  │       ││
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘       ││
│  │       │           │           │           │             ││
│  │       └───────────┴───────────┴───────────┘             ││
│  │                       │                                  ││
│  │              ┌────────┴────────┐                        ││
│  │              │  Widget Manager │                        ││
│  │              │   (GridStack)   │                        ││
│  │              └────────┬────────┘                        ││
│  └───────────────────────┼─────────────────────────────────┘│
│                          │                                   │
│              ┌───────────┴───────────┐                      │
│              │   API Client (fetch)  │                      │
│              │        + SSE          │                      │
│              └───────────┬───────────┘                      │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTP/SSE
┌──────────────────────────┼──────────────────────────────────┐
│                    Router (Server)                          │
│              ┌───────────┴───────────┐                      │
│              │    Python HTTP Server │                      │
│              │      (api-server.py)  │                      │
│              └───────────┬───────────┘                      │
│                          │                                   │
│    ┌─────────┬───────────┼───────────┬─────────┐           │
│    │         │           │           │         │           │
│    ▼         ▼           ▼           ▼         ▼           │
│ ┌──────┐ ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐        │
│ │/sys/ │ │/proc/│   │systemd│   │nftables│ │Prom- │        │
│ │class/│ │net/  │   │dbus   │   │ rules │ │etheus│        │
│ │net/  │ │...   │   │       │   │       │ │      │        │
│ └──────┘ └──────┘   └──────┘   └──────┘   └──────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Frontend Components

#### Widget Base Classes

```javascript
// js/widgets/base-widget.js
class BaseWidget {
  constructor(config) {
    this.id = config.id;
    this.title = config.title || 'Widget';
    this.refreshInterval = config.refreshInterval || 5000;
    this.container = null;
    this.intervalId = null;
  }

  // Called once to get widget HTML structure
  getMarkup() {
    throw new Error('Subclass must implement getMarkup()');
  }

  // Called after widget is added to DOM
  onMounted() {}

  // Called on each refresh cycle
  async onTick() {
    throw new Error('Subclass must implement onTick()');
  }

  // Called when widget is removed
  onDestroy() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
    }
  }

  // Start the refresh cycle
  start() {
    this.onTick();
    this.intervalId = setInterval(() => this.onTick(), this.refreshInterval);
  }

  // Helper for API calls
  async fetchAPI(endpoint) {
    const response = await fetch(`/api${endpoint}`);
    if (!response.ok) throw new Error(`API error: ${response.status}`);
    return response.json();
  }
}
```

#### Traffic Graph Widget

```javascript
// js/widgets/traffic-graph.js
class TrafficGraphWidget extends BaseWidget {
  constructor(config) {
    super(config);
    this.title = 'Traffic';
    this.chart = null;
    this.dataPoints = 60; // 5 minutes at 5s intervals
    this.history = {
      labels: [],
      rxData: [],
      txData: []
    };
  }

  getMarkup() {
    return `
      <div class="widget traffic-widget">
        <div class="widget-header">
          <h3>${this.title}</h3>
          <select class="interface-select">
            <option value="wan">WAN</option>
            <option value="lan">LAN</option>
          </select>
        </div>
        <div class="widget-body">
          <canvas id="traffic-chart-${this.id}"></canvas>
        </div>
      </div>
    `;
  }

  onMounted() {
    const ctx = document.getElementById(`traffic-chart-${this.id}`);
    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: this.history.labels,
        datasets: [
          {
            label: 'RX',
            data: this.history.rxData,
            borderColor: '#10b981',
            backgroundColor: 'rgba(16, 185, 129, 0.1)',
            fill: true,
            tension: 0.4
          },
          {
            label: 'TX',
            data: this.history.txData,
            borderColor: '#3b82f6',
            backgroundColor: 'rgba(59, 130, 246, 0.1)',
            fill: true,
            tension: 0.4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            beginAtZero: true,
            ticks: {
              callback: (value) => this.formatBytes(value) + '/s'
            }
          }
        },
        plugins: {
          legend: {
            position: 'bottom'
          }
        }
      }
    });
  }

  async onTick() {
    const data = await this.fetchAPI('/interfaces/stats');
    const iface = this.container.querySelector('.interface-select').value;
    const stats = data[iface];

    // Update history
    const now = new Date().toLocaleTimeString();
    this.history.labels.push(now);
    this.history.rxData.push(stats.rx_rate);
    this.history.txData.push(stats.tx_rate);

    // Keep only last N points
    if (this.history.labels.length > this.dataPoints) {
      this.history.labels.shift();
      this.history.rxData.shift();
      this.history.txData.shift();
    }

    this.chart.update('none'); // Update without animation
  }

  formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }
}
```

#### System Gauge Widget

```javascript
// js/widgets/system-gauge.js
class SystemGaugeWidget extends BaseWidget {
  constructor(config) {
    super(config);
    this.title = 'System';
    this.cpuChart = null;
    this.memChart = null;
  }

  getMarkup() {
    return `
      <div class="widget system-widget">
        <div class="widget-header">
          <h3>${this.title}</h3>
        </div>
        <div class="widget-body gauge-container">
          <div class="gauge-item">
            <canvas id="cpu-gauge-${this.id}"></canvas>
            <div class="gauge-label">CPU</div>
            <div class="gauge-value" id="cpu-value-${this.id}">--%</div>
          </div>
          <div class="gauge-item">
            <canvas id="mem-gauge-${this.id}"></canvas>
            <div class="gauge-label">Memory</div>
            <div class="gauge-value" id="mem-value-${this.id}">--%</div>
          </div>
        </div>
      </div>
    `;
  }

  onMounted() {
    const gaugeOptions = {
      type: 'doughnut',
      options: {
        circumference: 180,
        rotation: 270,
        cutout: '75%',
        plugins: { legend: { display: false } }
      }
    };

    this.cpuChart = new Chart(
      document.getElementById(`cpu-gauge-${this.id}`),
      {
        ...gaugeOptions,
        data: {
          datasets: [{
            data: [0, 100],
            backgroundColor: ['#3b82f6', '#1e293b']
          }]
        }
      }
    );

    this.memChart = new Chart(
      document.getElementById(`mem-gauge-${this.id}`),
      {
        ...gaugeOptions,
        data: {
          datasets: [{
            data: [0, 100],
            backgroundColor: ['#10b981', '#1e293b']
          }]
        }
      }
    );
  }

  async onTick() {
    const data = await this.fetchAPI('/system/resources');

    // Update CPU gauge
    this.cpuChart.data.datasets[0].data = [data.cpu, 100 - data.cpu];
    this.cpuChart.update('none');
    document.getElementById(`cpu-value-${this.id}`).textContent =
      `${data.cpu.toFixed(1)}%`;

    // Update Memory gauge
    this.memChart.data.datasets[0].data = [data.memory, 100 - data.memory];
    this.memChart.update('none');
    document.getElementById(`mem-value-${this.id}`).textContent =
      `${data.memory.toFixed(1)}%`;
  }
}
```

### 2. Backend API Structure

#### API Server (Python)

```python
#!/usr/bin/env python3
"""Enhanced router dashboard API server"""

import http.server
import socketserver
import subprocess
import json
import os
import re
from urllib.parse import urlparse, parse_qs
from pathlib import Path

class RouterAPIHandler(http.server.SimpleHTTPRequestHandler):

    # API route handlers
    API_ROUTES = {
        '/api/system/status': 'get_system_status',
        '/api/system/resources': 'get_system_resources',
        '/api/interfaces/stats': 'get_interface_stats',
        '/api/connections/list': 'get_connections',
        '/api/services/status': 'get_services_status',
        '/api/firewall/stats': 'get_firewall_stats',
        '/api/traffic/live': 'stream_traffic',  # SSE endpoint
    }

    def do_GET(self):
        parsed = urlparse(self.path)

        # Check if this is an API route
        if parsed.path in self.API_ROUTES:
            handler = getattr(self, self.API_ROUTES[parsed.path])
            handler(parse_qs(parsed.query))
        elif parsed.path == '/' or parsed.path == '/index.html':
            self.serve_dashboard()
        elif parsed.path.startswith('/js/') or parsed.path.startswith('/css/'):
            self.serve_static(parsed.path)
        else:
            self.send_error(404)

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def get_system_status(self, params):
        """System status endpoint"""
        data = {
            'hostname': self.read_file('/proc/sys/kernel/hostname').strip(),
            'uptime': self.get_uptime(),
            'kernel': self.read_file('/proc/version').split()[2],
            'timestamp': self.get_timestamp(),
        }
        self.send_json(data)

    def get_system_resources(self, params):
        """CPU and memory usage"""
        # CPU usage from /proc/stat
        cpu = self.calculate_cpu_usage()

        # Memory from /proc/meminfo
        meminfo = self.parse_meminfo()
        mem_total = meminfo.get('MemTotal', 0)
        mem_available = meminfo.get('MemAvailable', 0)
        mem_used_pct = ((mem_total - mem_available) / mem_total * 100) if mem_total > 0 else 0

        data = {
            'cpu': cpu,
            'memory': mem_used_pct,
            'memory_total': mem_total,
            'memory_available': mem_available,
            'load_avg': self.read_file('/proc/loadavg').split()[:3],
        }
        self.send_json(data)

    def get_interface_stats(self, params):
        """Interface statistics"""
        interfaces = {}
        net_path = Path('/sys/class/net')

        for iface_path in net_path.iterdir():
            if iface_path.name.startswith(('lo', 'docker', 'veth', 'br-')):
                continue

            iface = iface_path.name
            stats_path = iface_path / 'statistics'

            interfaces[iface] = {
                'device': iface,
                'state': self.read_file(iface_path / 'operstate').strip().upper(),
                'rx_bytes': int(self.read_file(stats_path / 'rx_bytes') or 0),
                'tx_bytes': int(self.read_file(stats_path / 'tx_bytes') or 0),
                'rx_packets': int(self.read_file(stats_path / 'rx_packets') or 0),
                'tx_packets': int(self.read_file(stats_path / 'tx_packets') or 0),
                'rx_errors': int(self.read_file(stats_path / 'rx_errors') or 0),
                'tx_errors': int(self.read_file(stats_path / 'tx_errors') or 0),
                'rx_rate': self.get_rate(iface, 'rx'),
                'tx_rate': self.get_rate(iface, 'tx'),
                'ipv4': self.get_ipv4(iface),
            }

        self.send_json(interfaces)

    def get_connections(self, params):
        """Connection tracking information"""
        try:
            result = subprocess.run(
                ['conntrack', '-L', '-o', 'extended'],
                capture_output=True, text=True, timeout=5
            )
            # Parse conntrack output (simplified)
            connections = []
            for line in result.stdout.strip().split('\n')[:100]:  # Limit to 100
                # Parse line into connection dict
                conn = self.parse_conntrack_line(line)
                if conn:
                    connections.append(conn)

            count = int(self.read_file('/proc/sys/net/netfilter/nf_conntrack_count') or 0)
            max_count = int(self.read_file('/proc/sys/net/netfilter/nf_conntrack_max') or 0)

            self.send_json({
                'count': count,
                'max': max_count,
                'connections': connections
            })
        except Exception as e:
            self.send_json({'error': str(e)}, 500)

    def get_services_status(self, params):
        """Systemd services status"""
        services = ['router-dashboard', 'caddy', 'prometheus', 'grafana',
                   'netdata', 'nftables', 'technitium-dns-server']

        result = []
        for service in services:
            try:
                status = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True, text=True, timeout=2
                )
                result.append({
                    'name': service,
                    'status': status.stdout.strip(),
                    'active': status.returncode == 0
                })
            except:
                result.append({
                    'name': service,
                    'status': 'unknown',
                    'active': False
                })

        self.send_json({'services': result})

    def get_firewall_stats(self, params):
        """nftables statistics"""
        try:
            result = subprocess.run(
                ['nft', '-j', 'list', 'ruleset'],
                capture_output=True, text=True, timeout=5
            )
            # Parse and summarize nftables JSON output
            data = json.loads(result.stdout)
            # Extract relevant statistics
            self.send_json({
                'rules': self.count_nft_rules(data),
                'flowtable_active': self.check_flowtable(data)
            })
        except Exception as e:
            self.send_json({'error': str(e)}, 500)

    def stream_traffic(self, params):
        """Server-Sent Events for real-time traffic"""
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

        import time
        try:
            while True:
                data = self.get_current_traffic()
                self.wfile.write(f"data: {json.dumps(data)}\n\n".encode())
                self.wfile.flush()
                time.sleep(1)
        except:
            pass

    # Helper methods
    def read_file(self, path):
        try:
            with open(path, 'r') as f:
                return f.read()
        except:
            return ''

    def get_uptime(self):
        uptime_secs = float(self.read_file('/proc/uptime').split()[0])
        days = int(uptime_secs // 86400)
        hours = int((uptime_secs % 86400) // 3600)
        minutes = int((uptime_secs % 3600) // 60)
        return f"up {days}d {hours}h {minutes}m"

    def get_timestamp(self):
        from datetime import datetime
        return datetime.now().isoformat()

    # ... additional helper methods
```

### 3. NixOS Module Structure

```nix
# modules/router-dashboard.nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-dashboard;

  # Package dashboard static files
  dashboardStatic = pkgs.stdenv.mkDerivation {
    name = "router-dashboard-static";
    src = ./router-dashboard;
    installPhase = ''
      mkdir -p $out
      cp -r * $out/
    '';
  };

  # Enhanced API server
  apiServer = pkgs.writeScript "router-api-server.py" (
    builtins.readFile ./router-dashboard/api/server.py
  );

in {
  options.services.router-dashboard = {
    enable = mkEnableOption "enhanced router dashboard";

    port = mkOption {
      type = types.port;
      default = 8888;
      description = "Port for the dashboard";
    };

    bind-address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind to";
    };

    theme = mkOption {
      type = types.enum [ "dark" "light" ];
      default = "dark";
      description = "Dashboard theme";
    };

    refreshInterval = mkOption {
      type = types.int;
      default = 5;
      description = "Widget refresh interval in seconds";
    };

    interfaces = mkOption {
      type = types.listOf (types.submodule {
        options = {
          device = mkOption { type = types.str; };
          label = mkOption { type = types.str; };
          role = mkOption {
            type = types.enum [ "wan" "lan" "opt" "mgmt" ];
            default = "opt";
          };
        };
      });
      default = [];
      description = "Network interfaces to monitor";
    };

    widgets = mkOption {
      type = types.submodule {
        options = {
          traffic = mkEnableOption "traffic graph widget" // { default = true; };
          system = mkEnableOption "system resources widget" // { default = true; };
          interfaces = mkEnableOption "interface status widget" // { default = true; };
          connections = mkEnableOption "connections widget" // { default = true; };
          services = mkEnableOption "services status widget" // { default = true; };
          firewall = mkEnableOption "firewall stats widget" // { default = true; };
        };
      };
      default = {};
    };
  };

  config = mkIf cfg.enable {
    systemd.services.router-dashboard = {
      description = "Enhanced Router Dashboard";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DASHBOARD_PORT = toString cfg.port;
        DASHBOARD_BIND = cfg.bind-address;
        DASHBOARD_THEME = cfg.theme;
        DASHBOARD_REFRESH = toString cfg.refreshInterval;
        DASHBOARD_STATIC = "${dashboardStatic}";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${apiServer}";
        Restart = "always";
        RestartSec = "5s";

        # Security hardening
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Capabilities for network stats
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      };

      path = with pkgs; [
        iproute2
        procps
        conntrack-tools
        nftables
        coreutils
      ];
    };

    networking.firewall.allowedTCPPorts =
      mkIf config.networking.firewall.enable [ cfg.port ];
  };
}
```

## Data Sources

### System Information
| Data | Source | Update Frequency |
|------|--------|------------------|
| CPU Usage | `/proc/stat` calculation | 5s |
| Memory | `/proc/meminfo` | 5s |
| Load Average | `/proc/loadavg` | 5s |
| Uptime | `/proc/uptime` | 30s |
| Hostname | `/proc/sys/kernel/hostname` | static |

### Network Statistics
| Data | Source | Update Frequency |
|------|--------|------------------|
| Interface bytes | `/sys/class/net/*/statistics/*` | 5s |
| Interface state | `/sys/class/net/*/operstate` | 5s |
| IP addresses | `ip addr` command | 30s |
| Connections | `/proc/sys/net/netfilter/nf_conntrack_*` | 5s |
| Connection list | `conntrack -L` | 10s |

### Services
| Data | Source | Update Frequency |
|------|--------|------------------|
| Service status | `systemctl is-active` | 30s |
| Service control | `systemctl start/stop/restart` | on-demand |

### Firewall
| Data | Source | Update Frequency |
|------|--------|------------------|
| nftables rules | `nft -j list ruleset` | 30s |
| Rule counters | nftables JSON output | 30s |
| Flowtable stats | nftables flowtable info | 30s |

## Security Considerations

1. **Bind Address**: Default to LAN interface only
2. **No Auth by Default**: Dashboard assumes LAN access is trusted
3. **Read-Only by Default**: Service control requires explicit enable
4. **Capability Restrictions**: Minimal capabilities for network stats
5. **systemd Hardening**: DynamicUser, ProtectSystem, etc.

## Future Enhancements

1. **Authentication**: Optional basic auth or OAuth2 proxy
2. **HTTPS**: Integration with Caddy reverse proxy
3. **Prometheus Integration**: Use Prometheus for historical data
4. **Alerting**: Integration with alertmanager
5. **Mobile App**: PWA or native app for mobile monitoring
