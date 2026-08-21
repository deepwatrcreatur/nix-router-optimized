#!/usr/bin/env python3
"""
Kea DHCP Metrics Exporter & Health Monitor
Queries Kea DHCP4 control socket (/run/kea/dhcp4.sock), calculates pool utilization,
exposes Prometheus metrics on HTTP, updates /run/router/kea-metrics.json, and logs
threshold warnings/errors to journalctl.
"""

import os
import sys
import json
import time
import socket
import csv
import logging
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger('router-kea-exporter')

KEA_SOCKET_PATH = os.environ.get('KEA_SOCKET_PATH', '/run/kea/dhcp4.sock')
KEA_LEASE_FILES = [
    Path('/var/lib/private/kea/dhcp4.leases.2'),
    Path('/var/lib/private/kea/dhcp4.leases'),
    Path('/var/lib/kea/dhcp4.leases.2'),
    Path('/var/lib/kea/dhcp4.leases'),
]
STATUS_JSON_PATH = Path('/run/router/kea-metrics.json')
DHCP_STATUS_PATH = Path('/run/router/dhcp-status.json')
EXPORT_PORT = int(os.environ.get('KEA_EXPORTER_PORT', 9547))

METRICS_CACHE = {
    'kea_up': 0,
    'pkt4_ack_received': 0,
    'pkt4_nak_sent': 0,
    'declined_addresses': 0,
    'assigned_addresses': 0,
    'cumulative_assigned_addresses': 0,
    'total_addresses': 0,
    'pool_utilization_percent': 0.0,
    'nak_rate_per_min': 0.0,
    'last_update': 0.0,
}
PREV_NAK = {'count': 0, 'time': 0.0}

def query_kea_socket(command="statistic-get-all"):
    if not os.path.exists(KEA_SOCKET_PATH):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3.0)
        s.connect(KEA_SOCKET_PATH)
        payload = json.dumps({"command": command, "arguments": {}}).encode("utf-8")
        s.sendall(payload)
        s.shutdown(socket.SHUT_WR)

        chunks = []
        while True:
            data = s.recv(4096)
            if not data:
                break
            chunks.append(data)
        s.close()

        res = json.loads(b"".join(chunks).decode("utf-8"))
        if res.get("result") == 0:
            return res.get("arguments", {})
    except Exception as e:
        logger.debug(f"Control socket query error: {e}")
    return None

def parse_kea_leases_fallback():
    now = int(time.time())
    active_count = 0
    declined_count = 0
    for lfile in KEA_LEASE_FILES:
        if not lfile.exists():
            continue
        try:
            with lfile.open(newline='') as h:
                reader = csv.DictReader(h)
                for row in reader:
                    if not row:
                        continue
                    try:
                        state = int((row.get('state') or '0').strip() or '0')
                        expire = int((row.get('expire') or '0').strip() or '0')
                    except ValueError:
                        continue
                    if state == 1 or state == 2:  # DECLINED
                        declined_count += 1
                    elif state == 0 and expire > now:
                        active_count += 1
        except Exception:
            pass
    return active_count, declined_count

def update_metrics():
    global METRICS_CACHE, PREV_NAK
    now = time.time()
    args = query_kea_socket("statistic-get-all")

    if args is not None:
        METRICS_CACHE['kea_up'] = 1
        def get_val(key, default=0):
            val = args.get(key)
            if val and isinstance(val, list) and len(val) > 0 and len(val[0]) > 0:
                return val[0][0]
            return default

        ack = get_val('pkt4-ack-received')
        nak = get_val('pkt4-nak-sent')
        declined = get_val('declined-addresses')
        assigned = get_val('assigned-addresses')
        cum_assigned = get_val('cumulative-assigned-addresses')

        total = get_val('subnet[1].total-addresses', 0)
        if total == 0:
            total = get_val('total-addresses', 0)
    else:
        METRICS_CACHE['kea_up'] = 0
        assigned, declined = parse_kea_leases_fallback()
        ack = 0
        nak = 0
        cum_assigned = assigned
        total = 0

    if total <= 0:
        env_total = os.environ.get('KEA_TOTAL_ADDRESSES')
        if env_total and env_total.isdigit():
            total = int(env_total)
        else:
            total = 5842  # default LAN slice pool capacity (10.10.200.1 - 10.10.222.254)

    utilization = ((assigned + declined) / total * 100.0) if total > 0 else 0.0

    nak_rate = 0.0
    if PREV_NAK['time'] > 0 and now > PREV_NAK['time']:
        dt = now - PREV_NAK['time']
        dn = max(0, nak - PREV_NAK['count'])
        nak_rate = (dn / dt) * 60.0

    PREV_NAK['count'] = nak
    PREV_NAK['time'] = now

    METRICS_CACHE.update({
        'pkt4_ack_received': ack,
        'pkt4_nak_sent': nak,
        'declined_addresses': declined,
        'assigned_addresses': assigned,
        'cumulative_assigned_addresses': cum_assigned,
        'total_addresses': total,
        'pool_utilization_percent': round(utilization, 2),
        'nak_rate_per_min': round(nak_rate, 2),
        'last_update': now
    })

    if utilization > 90.0:
        logger.error(f"Kea DHCP Critical: IP pool utilization ({utilization:.1f}%) > 90%")
    elif utilization > 75.0:
        logger.warning(f"Kea DHCP Warning: IP pool utilization ({utilization:.1f}%) > 75%")

    if declined > 5:
        logger.warning(f"Kea DHCP Warning: declined-addresses count ({declined}) > 5")

    if nak_rate > 10.0:
        logger.error(f"Kea DHCP Critical: pkt4-nak-sent rate ({nak_rate:.1f}/min) > 10/min")

    try:
        STATUS_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(STATUS_JSON_PATH, 'w') as f:
            json.dump(METRICS_CACHE, f, indent=2)

        dhcp_status_data = {
            "available": True,
            "provider": "kea",
            "lastUpdated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "poolUtilization": METRICS_CACHE['pool_utilization_percent'],
            "assignedAddresses": METRICS_CACHE['assigned_addresses'],
            "declinedAddresses": METRICS_CACHE['declined_addresses'],
            "totalAddresses": METRICS_CACHE['total_addresses'],
            "nakSentCount": METRICS_CACHE['pkt4_nak_sent'],
            "ackReceivedCount": METRICS_CACHE['pkt4_ack_received'],
        }
        with open(DHCP_STATUS_PATH, 'w') as f:
            json.dump(dhcp_status_data, f, indent=2)
    except Exception as e:
        logger.debug(f"Failed to write status JSON: {e}")

class MetricsHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == '/metrics':
            update_metrics()
            m = METRICS_CACHE
            lines = [
                "# HELP kea_dhcp4_up Kea DHCP4 daemon control socket responsiveness",
                "# TYPE kea_dhcp4_up gauge",
                f"kea_dhcp4_up {m['kea_up']}",
                "# HELP kea_dhcp4_assigned_addresses Number of currently assigned DHCPv4 addresses",
                "# TYPE kea_dhcp4_assigned_addresses gauge",
                f"kea_dhcp4_assigned_addresses {m['assigned_addresses']}",
                "# HELP kea_dhcp4_declined_addresses Number of DECLINED DHCPv4 addresses",
                "# TYPE kea_dhcp4_declined_addresses gauge",
                f"kea_dhcp4_declined_addresses {m['declined_addresses']}",
                "# HELP kea_dhcp4_cumulative_assigned_addresses Total cumulative assigned DHCPv4 addresses",
                "# TYPE kea_dhcp4_cumulative_assigned_addresses counter",
                f"kea_dhcp4_cumulative_assigned_addresses {m['cumulative_assigned_addresses']}",
                "# HELP kea_dhcp4_pkt4_ack_received Total DHCPACK packets received/processed",
                "# TYPE kea_dhcp4_pkt4_ack_received counter",
                f"kea_dhcp4_pkt4_ack_received {m['pkt4_ack_received']}",
                "# HELP kea_dhcp4_pkt4_nak_sent Total DHCPNAK packets sent",
                "# TYPE kea_dhcp4_pkt4_nak_sent counter",
                f"kea_dhcp4_pkt4_nak_sent {m['pkt4_nak_sent']}",
                "# HELP kea_dhcp4_total_addresses Total capacity of dynamic DHCPv4 address pool",
                "# TYPE kea_dhcp4_total_addresses gauge",
                f"kea_dhcp4_total_addresses {m['total_addresses']}",
                "# HELP kea_dhcp4_pool_utilization_percent Dynamic DHCPv4 pool utilization percentage",
                "# TYPE kea_dhcp4_pool_utilization_percent gauge",
                f"kea_dhcp4_pool_utilization_percent {m['pool_utilization_percent']}",
                ""
            ]
            body = "\n".join(lines).encode('utf-8')
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path in ('/status', '/api/dhcp/status'):
            update_metrics()
            body = json.dumps(METRICS_CACHE, indent=2).encode('utf-8')
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404, "Not Found")

def main():
    parser = argparse.ArgumentParser(description="Kea DHCP Metrics Exporter")
    parser.add_argument("--port", type=int, default=EXPORT_PORT, help="Exporter HTTP port")
    parser.add_argument("--once", action="store_true", help="Run metric update once and exit")
    args = parser.parse_args()

    update_metrics()
    if args.once:
        print(json.dumps(METRICS_CACHE, indent=2))
        sys.exit(0)

    server = HTTPServer(('0.0.0.0', args.port), MetricsHandler)
    logger.info(f"Starting router-kea-exporter on port {args.port}...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    main()
