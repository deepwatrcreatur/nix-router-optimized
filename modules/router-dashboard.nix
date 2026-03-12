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
      local label=$2
      local role=$3
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
      
      echo "\"$iface\": {\"device\": \"$iface\", \"label\": \"$label\", \"role\": \"$role\", \"status\": \"$status\", \"ip\": \"$ip_addr\", \"rx\": $rx_bytes, \"tx\": $tx_bytes, \"rx_rate\": $rx_rate, \"tx_rate\": $tx_rate}"
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
    
    ${concatStringsSep "\n" (imap0 (idx: iface: ''
      get_interface_stats "${iface.device}" "${iface.label}" "${iface.role}"
      ${if idx < (length cfg.interfaces) - 1 then "echo \",\"" else ""}
    '') cfg.interfaces)}
    
    echo "  }"
    echo "}"
  '';

  # Simple web dashboard HTML - read from external file to avoid Nix/JavaScript syntax conflicts
  dashboardHTML = ./dashboard.html;

in {
  options.services.router-dashboard = {
    enable = mkEnableOption "router web dashboard";
    
    port = mkOption {
      type = types.port;
      default = 8888;
      description = "Port for the router dashboard";
    };
    
    interfaces = mkOption {
      type = types.listOf (types.submodule {
        options = {
          device = mkOption {
            type = types.str;
            description = "Network interface device name (e.g., eth0, ens18)";
          };
          label = mkOption {
            type = types.str;
            description = "Human-readable label for the interface (e.g., WAN, LAN, OPT1)";
          };
          role = mkOption {
            type = types.enum [ "wan" "lan" "opt" "mgmt" ];
            default = "opt";
            description = "Interface role: wan (external), lan (internal), opt (optional), mgmt (management)";
          };
        };
      });
      default = [];
      example = [
        { device = "ens17"; label = "WAN"; role = "wan"; }
        { device = "ens16"; label = "LAN"; role = "lan"; }
        { device = "ens18"; label = "Management"; role = "mgmt"; }
      ];
      description = "Network interfaces to monitor with labels";
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
