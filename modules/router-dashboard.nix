# Router web dashboard with real-time traffic monitoring
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.router-dashboard;
  
  # Dashboard API script that provides router stats
  dashboardAPI = pkgs.writeShellScriptBin "router-api" ''
    #!/bin/sh
    set -e
    
    get_interface_stats() {
      local iface=$1
      local ip_addr=$(${pkgs.iproute2}/bin/ip -4 addr show $iface 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
      local status="down"
      local rx_bytes=0
      local tx_bytes=0
      local rx_rate=0
      local tx_rate=0
      
      if ${pkgs.iproute2}/bin/ip link show $iface up &>/dev/null; then
        status="up"
        if [ -f /sys/class/net/$iface/statistics/rx_bytes ]; then
          rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes)
        fi
        if [ -f /sys/class/net/$iface/statistics/tx_bytes ]; then
          tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes)
        fi
        
        # Calculate rates (bytes/sec) - compare with previous reading
        if [ -f /tmp/router-api-$iface-rx ]; then
          local prev_rx=$(cat /tmp/router-api-$iface-rx)
          local prev_time=$(cat /tmp/router-api-$iface-time)
          local curr_time=$(date +%s)
          local time_diff=$((curr_time - prev_time))
          if [ $time_diff -gt 0 ]; then
            rx_rate=$(( (rx_bytes - prev_rx) / time_diff ))
            local prev_tx=$(cat /tmp/router-api-$iface-tx)
            tx_rate=$(( (tx_bytes - prev_tx) / time_diff ))
          fi
        fi
        
        # Store current values for next calculation
        echo $rx_bytes > /tmp/router-api-$iface-rx
        echo $tx_bytes > /tmp/router-api-$iface-tx
        echo $(date +%s) > /tmp/router-api-$iface-time
      fi
      
      echo "\"$iface\": {\"status\": \"$status\", \"ip\": \"$ip_addr\", \"rx\": $rx_bytes, \"tx\": $tx_bytes, \"rx_rate\": $rx_rate, \"tx_rate\": $tx_rate}"
    }
    
    # Get system info
    hostname=$(${pkgs.hostname}/bin/hostname)
    uptime=$(${pkgs.procps}/bin/uptime -p | ${pkgs.gnused}/bin/sed 's/up //')
    active_conns=$(${pkgs.conntrack-tools}/bin/conntrack -C 2>/dev/null || echo 0)
    
    # Build JSON response
    echo "{"
    echo "  \"hostname\": \"$hostname\","
    echo "  \"uptime\": \"$uptime\","
    echo "  \"connections\": $active_conns,"
    echo "  \"interfaces\": {"
    
    ${concatStringsSep "\n" (map (iface: ''
      get_interface_stats "${iface}"
      echo ","
    '') (init cfg.interfaces))}
    
    ${if cfg.interfaces != [] then ''
      get_interface_stats "${last cfg.interfaces}"
    '' else ""}
    
    echo "  }"
    echo "}"
  '';

  # Simple web dashboard HTML
  dashboardHTML = pkgs.writeText "router-dashboard.html" ''
    <!DOCTYPE html>
    <html>
    <head>
      <title>Router Dashboard</title>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          min-height: 100vh;
          padding: 20px;
        }
        .container {
          max-width: 1200px;
          margin: 0 auto;
        }
        .header {
          background: white;
          border-radius: 10px;
          padding: 20px;
          margin-bottom: 20px;
          box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
          color: #667eea;
          margin-bottom: 10px;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 15px;
          margin-bottom: 20px;
        }
        .stat-card {
          background: white;
          border-radius: 10px;
          padding: 20px;
          box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
          color: #666;
          font-size: 14px;
          margin-bottom: 10px;
        }
        .stat-card .value {
          color: #667eea;
          font-size: 24px;
          font-weight: bold;
        }
        .interfaces {
          display: grid;
          gap: 15px;
        }
        .interface-card {
          background: white;
          border-radius: 10px;
          padding: 20px;
          box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .interface-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 15px;
        }
        .interface-name {
          font-size: 18px;
          font-weight: bold;
          color: #333;
        }
        .status {
          padding: 5px 15px;
          border-radius: 20px;
          font-size: 12px;
          font-weight: bold;
        }
        .status.up {
          background: #10b981;
          color: white;
        }
        .status.down {
          background: #ef4444;
          color: white;
        }
        .interface-info {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
          gap: 15px;
        }
        .info-item {
          padding: 10px;
          background: #f3f4f6;
          border-radius: 5px;
        }
        .info-label {
          font-size: 12px;
          color: #666;
          margin-bottom: 5px;
        }
        .info-value {
          font-size: 16px;
          font-weight: bold;
          color: #333;
        }
        .error {
          background: #fee2e2;
          color: #991b1b;
          padding: 15px;
          border-radius: 10px;
          margin-bottom: 20px;
        }
        .loading {
          text-align: center;
          padding: 40px;
          color: white;
          font-size: 18px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div id="error" class="error" style="display: none;"></div>
        <div id="loading" class="loading">Loading router data...</div>
        <div id="dashboard" style="display: none;">
          <div class="header">
            <h1 id="hostname">Router Dashboard</h1>
            <div class="stats">
              <div class="stat-card">
                <h3>Uptime</h3>
                <div class="value" id="uptime">-</div>
              </div>
              <div class="stat-card">
                <h3>Active Connections</h3>
                <div class="value" id="connections">-</div>
              </div>
            </div>
          </div>
          <div class="interfaces" id="interfaces"></div>
        </div>
      </div>

      <script>
        function formatBytes(bytes, rate = false) {
          if (bytes === 0) return '0 B' + (rate ${"?"} '/s' : '');
          const k = 1024;
          const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
          const i = Math.floor(Math.log(bytes) / Math.log(k));
          return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i] + (rate ${"?"} '/s' : '');
        }

        function updateDashboard() {
          fetch('/api/stats')
            .then(response => response.json())
            .then(data => {
              document.getElementById('loading').style.display = 'none';
              document.getElementById('dashboard').style.display = 'block';
              document.getElementById('error').style.display = 'none';
              
              document.getElementById('hostname').textContent = data.hostname || 'Router Dashboard';
              document.getElementById('uptime').textContent = data.uptime || '-';
              document.getElementById('connections').textContent = data.connections || '0';
              
              const interfacesDiv = document.getElementById('interfaces');
              interfacesDiv.innerHTML = '';
              
              for (const [name, iface] of Object.entries(data.interfaces || {})) {
                const card = document.createElement('div');
                card.className = 'interface-card';
                card.innerHTML = `
                  <div class="interface-header">
                    <div class="interface-name">''${name}</div>
                    <div class="status ''${iface.status}">''${iface.status.toUpperCase()}</div>
                  </div>
                  <div class="interface-info">
                    <div class="info-item">
                      <div class="info-label">IPv4 Address</div>
                      <div class="info-value">''${iface.ip || 'N/A'}</div>
                    </div>
                    <div class="info-item">
                      <div class="info-label">RX Total</div>
                      <div class="info-value">''${formatBytes(iface.rx)}</div>
                    </div>
                    <div class="info-item">
                      <div class="info-label">TX Total</div>
                      <div class="info-value">''${formatBytes(iface.tx)}</div>
                    </div>
                    <div class="info-item">
                      <div class="info-label">RX Rate</div>
                      <div class="info-value">''${formatBytes(iface.rx_rate, true)}</div>
                    </div>
                    <div class="info-item">
                      <div class="info-label">TX Rate</div>
                      <div class="info-value">''${formatBytes(iface.tx_rate, true)}</div>
                    </div>
                  </div>
                `;
                interfacesDiv.appendChild(card);
              }
            })
            .catch(error => {
              console.error('Error fetching stats:', error);
              document.getElementById('loading').style.display = 'none';
              document.getElementById('error').style.display = 'block';
              document.getElementById('error').textContent = 'Error loading router data: ' + error.message;
            });
        }

        // Update every 2 seconds
        updateDashboard();
        setInterval(updateDashboard, 2000);
      </script>
    </body>
    </html>
  '';
in {
  options.services.router-dashboard = {
    enable = mkEnableOption "router web dashboard";
    
    port = mkOption {
      type = types.port;
      default = 8888;
      description = "Port for the router dashboard";
    };
    
    interfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "wan" "lan" "guest" ];
      description = "Network interfaces to monitor";
    };
    
    bind-address = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "IP address to bind the dashboard to";
    };
  };

  config = mkIf cfg.enable {
    # Create a simple HTTP server for the dashboard
    systemd.services.router-dashboard = {
      description = "Router Dashboard HTTP Server";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
      };
      
      script = ''
        # Simple HTTP server using Python
        ${pkgs.python3}/bin/python3 -c '
import http.server
import socketserver
import subprocess
import json
from urllib.parse import urlparse

PORT = ${toString cfg.port}
BIND = "${cfg.bind-address}"

class RouterHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == "/api/stats":
            try:
                result = subprocess.run(
                    ["${dashboardAPI}/bin/router-api"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                
                self.send_response(200)
                self.send_header("Content-type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(result.stdout.encode())
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
        elif parsed_path.path == "/" or parsed_path.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            with open("${dashboardHTML}", "rb") as f:
                self.wfile.write(f.read())
        else:
            self.send_error(404)

with socketserver.TCPServer((BIND, PORT), RouterHandler) as httpd:
    print(f"Router dashboard serving on {BIND}:{PORT}")
    httpd.serve_forever()
'
      '';
    };

    # Allow dashboard port in firewall if using it
    networking.firewall.allowedTCPPorts = mkIf (config.networking.firewall.enable) [ cfg.port ];
  };
}
