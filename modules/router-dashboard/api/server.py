#!/usr/bin/env python3
"""
Enhanced Router Dashboard API Server
Provides REST endpoints for dashboard widgets
"""

import http.server
import socketserver
import subprocess
import json
import os
import re
import socket
import time
import urllib.request
import urllib.error
import threading
import select
from pathlib import Path
from urllib.parse import urlparse, parse_qs, urlencode

# Configuration from environment
PORT = int(os.environ.get('DASHBOARD_PORT', 8888))
BIND = os.environ.get('DASHBOARD_BIND', '0.0.0.0')
STATIC_DIR = os.environ.get('DASHBOARD_STATIC', '/etc/router-dashboard')
try:
    DASHBOARD_SERVICES = json.loads(os.environ.get('DASHBOARD_SERVICES', '[]'))
except json.JSONDecodeError:
    DASHBOARD_SERVICES = []
try:
    WOL_DEVICES = json.loads(os.environ.get('DASHBOARD_WOL_DEVICES', '[]'))
except json.JSONDecodeError:
    WOL_DEVICES = []

# Rate tracking for interface stats
RATE_CACHE = {}
RATE_CACHE_TIME = {}

# Technitium DNS Server configuration
TECHNITIUM_URL = os.environ.get('TECHNITIUM_URL', 'http://localhost:5380')
TECHNITIUM_API_KEY_FILE = os.environ.get('TECHNITIUM_API_KEY_FILE', '')
TECHNITIUM_TOKEN_CACHE = {'token': None, 'expires': 0}

# Speed test state
SPEEDTEST_STATE = {
    'running': False,
    'stage': None,
    'progress': 0,
    'result': None,
    'error': None,
    'thread': None
}


class RouterAPIHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler for router dashboard API and static files"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC_DIR, **kwargs)

    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

    def end_headers(self):
        """Disable caching for dashboard assets and API responses"""
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # API routes
        if path == '/api/system/status':
            self.handle_system_status()
        elif path == '/api/system/resources':
            self.handle_system_resources()
        elif path == '/api/interfaces/stats':
            self.handle_interface_stats()
        elif path == '/api/connections/summary':
            self.handle_connections_summary()
        elif path == '/api/connections/top':
            self.handle_connections_top(query)
        elif path == '/api/services/status':
            self.handle_services_status()
        elif path == '/api/firewall/stats':
            self.handle_firewall_stats()
        elif path == '/api/firewall/logs/recent':
            self.handle_firewall_logs_recent(query)
        elif path == '/api/firewall/logs/stream':
            self.handle_firewall_logs_stream(query)
        elif path == '/api/gateway/health':
            self.handle_gateway_health()
        elif path == '/api/dns/stats':
            self.handle_dns_stats()
        elif path == '/api/dhcp/leases':
            self.handle_dhcp_leases()
        elif path == '/api/fail2ban/status':
            self.handle_fail2ban_status()
        elif path == '/api/speedtest/status':
            self.handle_speedtest_status()
        elif path.startswith('/api/'):
            self.send_error(404, 'API endpoint not found')
        else:
            # Serve static files
            if path == '/':
                self.path = '/index.html'
            super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/api/speedtest/run':
            self.handle_speedtest_run()
        elif path == '/api/wol/wake':
            self.handle_wol_wake()
        else:
            self.send_error(404, 'API endpoint not found')

    def send_json(self, data, status=200):
        """Send JSON response"""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_error_json(self, status, message):
        """Send JSON error response"""
        self.send_json({'error': message}, status)

    # === API Handlers ===

    def handle_system_status(self):
        """System status endpoint"""
        try:
            hostname = self.read_file('/proc/sys/kernel/hostname').strip()
            uptime = self.get_uptime()
            kernel = self.read_file('/proc/version').split()[2] if self.read_file('/proc/version') else 'unknown'

            self.send_json({
                'hostname': hostname,
                'uptime': uptime,
                'kernel': kernel,
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
            })
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_system_resources(self):
        """CPU, memory, disk, load average"""
        try:
            # CPU usage
            cpu = self.get_cpu_usage()

            # Memory
            meminfo = self.parse_meminfo()
            mem_total = meminfo.get('MemTotal', 0)
            mem_available = meminfo.get('MemAvailable', 0)
            mem_used = mem_total - mem_available
            mem_percent = (mem_used / mem_total * 100) if mem_total > 0 else 0

            # Disk usage (root filesystem)
            disk_percent, disk_used, disk_total = self.get_disk_usage_detailed('/')

            # Load average
            loadavg = self.read_file('/proc/loadavg').split()[:3] if self.read_file('/proc/loadavg') else ['0', '0', '0']

            # Process count
            try:
                procs = len([d for d in os.listdir('/proc') if d.isdigit()])
            except:
                procs = 0

            self.send_json({
                'cpu': cpu,
                'memory': mem_percent,
                'memory_total': mem_total,
                'memory_used': mem_used,
                'memory_available': mem_available,
                'memory_total_human': self.format_bytes(mem_total),
                'memory_used_human': self.format_bytes(mem_used),
                'disk': disk_percent,
                'disk_total': disk_total,
                'disk_used': disk_used,
                'disk_total_human': self.format_bytes(disk_total),
                'disk_used_human': self.format_bytes(disk_used),
                'load_avg': loadavg,
                'processes': procs
            })
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_interface_stats(self):
        """Network interface statistics"""
        try:
            interfaces = {}
            net_path = Path('/sys/class/net')

            # Interface mapping (customize as needed)
            iface_map = {
                'ens17': 'wan',
                'ens16': 'lan',
                'ens18': 'mgmt',
                'eth0': 'wan',
                'eth1': 'lan'
            }

            for iface_path in net_path.iterdir():
                name = iface_path.name
                if name.startswith(('lo', 'docker', 'veth', 'br-', 'virbr')):
                    continue

                stats_path = iface_path / 'statistics'
                if not stats_path.exists():
                    continue

                rx_bytes = int(self.read_file(stats_path / 'rx_bytes') or 0)
                tx_bytes = int(self.read_file(stats_path / 'tx_bytes') or 0)

                # Calculate rates
                rx_rate, tx_rate = self.calculate_rates(name, rx_bytes, tx_bytes)

                # Get IP addresses
                ipv4 = self.get_ipv4(name)
                ipv6_list = self.get_ipv6(name)

                # Use mapped name or device name
                key = iface_map.get(name, name)

                interfaces[key] = {
                    'device': name,
                    'state': self.read_file(iface_path / 'operstate').strip().upper() or 'UNKNOWN',
                    'ipv4': ipv4,
                    'ipv6': ipv6_list,
                    'rx_bytes': rx_bytes,
                    'tx_bytes': tx_bytes,
                    'rx_rate': rx_rate,
                    'tx_rate': tx_rate,
                    'rx_packets': int(self.read_file(stats_path / 'rx_packets') or 0),
                    'tx_packets': int(self.read_file(stats_path / 'tx_packets') or 0),
                    'rx_errors': int(self.read_file(stats_path / 'rx_errors') or 0),
                    'tx_errors': int(self.read_file(stats_path / 'tx_errors') or 0)
                }

            self.send_json(interfaces)
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_connections_summary(self):
        """Connection tracking summary"""
        try:
            count = int(self.read_file('/proc/sys/net/netfilter/nf_conntrack_count') or 0)
            max_count = int(self.read_file('/proc/sys/net/netfilter/nf_conntrack_max') or 262144)

            # Get protocol breakdown using conntrack
            # Format with -o extended: "ipv4     2 tcp      6 ..." or "ipv4     2 udp      17 ..."
            by_protocol = {'tcp': 0, 'udp': 0, 'icmp': 0, 'other': 0}
            try:
                result = subprocess.run(
                    ['conntrack', '-L', '-o', 'extended'],
                    capture_output=True, text=True, timeout=3,
                    env={**os.environ, 'LC_ALL': 'C'}
                )
                for line in result.stdout.split('\n'):
                    if not line.strip():
                        continue
                    # Parse: "ipv4     2 tcp      6 ..." - protocol is 3rd field
                    parts = line.split()
                    if len(parts) >= 3:
                        proto = parts[2].lower()
                        if proto == 'tcp':
                            by_protocol['tcp'] += 1
                        elif proto == 'udp':
                            by_protocol['udp'] += 1
                        elif proto == 'icmp':
                            by_protocol['icmp'] += 1
                        else:
                            by_protocol['other'] += 1
            except:
                pass

            self.send_json({
                'count': count,
                'max': max_count,
                'by_protocol': by_protocol
            })
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_services_status(self):
        """Systemd services status"""
        services_to_check = DASHBOARD_SERVICES or [
            'nftables',
            'caddy',
            'prometheus',
            'grafana',
            'netdata'
        ]

        # Find systemctl - try common NixOS paths
        systemctl = None
        for path in ['/run/current-system/sw/bin/systemctl', '/usr/bin/systemctl', 'systemctl']:
            try:
                result = subprocess.run([path, '--version'], capture_output=True, timeout=2)
                if result.returncode == 0:
                    systemctl = path
                    break
            except:
                continue

        if not systemctl:
            self.send_json({'services': [], 'error': 'systemctl not found'})
            return

        results = []
        for service in services_to_check:
            results.append(self.get_service_status(systemctl, service))

        self.send_json({'services': results})

    def handle_firewall_stats(self):
        """nftables statistics"""
        try:
            result = subprocess.run(
                ['nft', '-j', 'list', 'ruleset'],
                capture_output=True, text=True, timeout=5
            )

            if result.returncode != 0:
                self.send_json({'error': 'Failed to get nftables stats'})
                return

            data = json.loads(result.stdout)
            rules_count = 0
            flowtable_active = False
            offloaded_flows = 0

            for item in data.get('nftables', []):
                if 'rule' in item:
                    rules_count += 1
                if 'flowtable' in item:
                    flowtable_active = True

            # Get flowtable flow count if available
            try:
                ft_result = subprocess.run(
                    ['conntrack', '-L', '-o', 'extended'],
                    capture_output=True, text=True, timeout=3
                )
                # Count flows with offload mark (simplified - actual implementation may vary)
                offloaded_flows = ft_result.stdout.count('[OFFLOAD]')
            except:
                pass

            # Get packet counters from interfaces
            packets_in = 0
            packets_out = 0
            try:
                for iface in ['ens16', 'ens17', 'ens18']:
                    rx = self.read_file(f'/sys/class/net/{iface}/statistics/rx_packets')
                    tx = self.read_file(f'/sys/class/net/{iface}/statistics/tx_packets')
                    if rx:
                        packets_in += int(rx)
                    if tx:
                        packets_out += int(tx)
            except:
                pass

            self.send_json({
                'rules_count': rules_count,
                'flowtable_active': flowtable_active,
                'offloaded_flows': offloaded_flows,
                'packets_in': packets_in,
                'packets_out': packets_out
            })
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_gateway_health(self):
        """Ping upstream gateways and DNS servers"""
        targets = [
            {'name': 'Gateway', 'host': self.get_default_gateway()},
            {'name': 'Cloudflare', 'host': '1.1.1.1'},
            {'name': 'Google', 'host': '8.8.8.8'},
        ]

        # Find ping binary - prefer setuid wrapper on NixOS
        ping_cmd = 'ping'
        for path in ['/run/wrappers/bin/ping', '/usr/bin/ping', 'ping']:
            try:
                test = subprocess.run([path, '-c', '1', '-W', '1', '127.0.0.1'],
                                     capture_output=True, timeout=3)
                if test.returncode == 0:
                    ping_cmd = path
                    break
            except:
                continue

        results = []
        for target in targets:
            if not target['host']:
                continue

            try:
                result = subprocess.run(
                    [ping_cmd, '-c', '3', '-W', '2', target['host']],
                    capture_output=True, text=True, timeout=10
                )

                latency = None
                loss = 100.0
                status = 'down'

                if result.returncode == 0:
                    # Parse ping output for latency
                    # Example: "rtt min/avg/max/mdev = 1.234/2.345/3.456/0.567 ms"
                    for line in result.stdout.split('\n'):
                        if 'avg' in line and '/' in line:
                            try:
                                parts = line.split('=')[1].strip().split('/')
                                latency = float(parts[1])
                            except:
                                pass
                        if 'packet loss' in line:
                            try:
                                loss = float(line.split('%')[0].split()[-1])
                            except:
                                pass

                    if latency is not None:
                        status = 'up'

                results.append({
                    'name': target['name'],
                    'host': target['host'],
                    'latency': latency,
                    'loss': loss,
                    'status': status
                })
            except Exception as e:
                results.append({
                    'name': target['name'],
                    'host': target['host'],
                    'latency': None,
                    'loss': 100.0,
                    'status': 'error'
                })

        self.send_json({'targets': results})

    def handle_connections_top(self, query):
        """Get top connections by various criteria"""
        try:
            limit = int(query.get('limit', ['10'])[0])
            filter_proto = query.get('filter', ['all'])[0]

            connections = []
            result = subprocess.run(
                ['conntrack', '-L', '-o', 'extended'],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, 'LC_ALL': 'C'}
            )

            for line in result.stdout.split('\n'):
                if not line.strip():
                    continue

                parts = line.split()
                if len(parts) < 10:
                    continue

                proto = parts[2].lower() if len(parts) > 2 else 'unknown'

                # Apply filter
                if filter_proto != 'all' and proto != filter_proto:
                    continue

                # Parse connection details
                conn = {'protocol': proto}

                # Extract timeout (4th field typically)
                try:
                    conn['timeout'] = int(parts[4]) if parts[4].isdigit() else None
                except:
                    conn['timeout'] = None

                # Parse src/dst from the line
                for part in parts:
                    if part.startswith('src='):
                        if 'src_ip' not in conn:
                            conn['src_ip'] = part.split('=')[1]
                    elif part.startswith('dst='):
                        if 'dst_ip' not in conn:
                            conn['dst_ip'] = part.split('=')[1]
                    elif part.startswith('sport='):
                        if 'src_port' not in conn:
                            conn['src_port'] = part.split('=')[1]
                    elif part.startswith('dport='):
                        if 'dst_port' not in conn:
                            conn['dst_port'] = part.split('=')[1]

                # Get state for TCP
                conn['state'] = None
                for state in ['ESTABLISHED', 'TIME_WAIT', 'SYN_SENT', 'SYN_RECV', 'FIN_WAIT', 'CLOSE_WAIT', 'CLOSE']:
                    if state in parts:
                        conn['state'] = state
                        break

                # Only add if we have the required fields
                if all(k in conn for k in ['src_ip', 'dst_ip', 'src_port', 'dst_port']):
                    connections.append(conn)

                if len(connections) >= limit:
                    break

            self.send_json({'connections': connections})
        except Exception as e:
            self.send_error_json(500, str(e))

    def handle_dns_stats(self):
        """Get DNS statistics from Technitium"""
        try:
            token = self.get_technitium_token()
            if not token:
                # Return mock/empty data if Technitium not available
                self.send_json({
                    'available': False,
                    'message': 'Technitium DNS not configured or unavailable'
                })
                return

            # Get dashboard stats
            stats_url = f"{TECHNITIUM_URL}/api/dashboard/stats/get?token={token}&type=LastHour&utc=true"
            stats_data = self.fetch_technitium_api(stats_url)

            if not stats_data or stats_data.get('status') == 'error':
                self.send_json({
                    'available': False,
                    'message': stats_data.get('errorMessage', 'Failed to get DNS stats')
                })
                return

            response = stats_data.get('response', {})
            stats = response.get('stats', response)
            main_chart = stats.get('mainChartData', response.get('mainChartData', {}))

            # Calculate totals from chart data
            total_queries = self.sum_numeric_values(
                main_chart.get('totalQueries'),
                stats.get('totalQueries'),
                response.get('totalQueries')
            )
            total_blocked = self.sum_numeric_values(
                main_chart.get('totalBlockedQueries'),
                stats.get('totalBlockedQueries'),
                response.get('totalBlockedQueries')
            )
            total_cached = self.sum_numeric_values(
                main_chart.get('totalCachedQueries'),
                stats.get('totalCachedQueries'),
                response.get('totalCachedQueries')
            )

            # Get top stats
            top_url = f"{TECHNITIUM_URL}/api/dashboard/stats/getTop?token={token}&type=LastHour&statsType=TopDomains&limit=5&utc=true"
            top_data = self.fetch_technitium_api(top_url)
            top_domains = []
            if top_data and top_data.get('status') == 'ok':
                top_response = top_data.get('response', {})
                top_domains = (top_response.get('topDomains')
                               or top_response.get('domains')
                               or top_response.get('items')
                               or [])[:5]

            # Get top clients
            clients_url = f"{TECHNITIUM_URL}/api/dashboard/stats/getTop?token={token}&type=LastHour&statsType=TopClients&limit=5&utc=true"
            clients_data = self.fetch_technitium_api(clients_url)
            top_clients = []
            if clients_data and clients_data.get('status') == 'ok':
                clients_response = clients_data.get('response', {})
                top_clients = (clients_response.get('topClients')
                               or clients_response.get('clients')
                               or clients_response.get('items')
                               or [])[:5]

            self.send_json({
                'available': True,
                'totalQueries': total_queries,
                'totalBlocked': total_blocked,
                'totalCached': total_cached,
                'blockRate': (total_blocked / total_queries * 100) if total_queries > 0 else 0,
                'cacheRate': (total_cached / total_queries * 100) if total_queries > 0 else 0,
                'topDomains': top_domains,
                'topClients': top_clients
            })
        except Exception as e:
            self.send_json({
                'available': False,
                'message': str(e)
            })

    def handle_dhcp_leases(self):
        """Get DHCP lease information from Technitium"""
        try:
            token = self.get_technitium_token()
            if not token:
                self.send_json({
                    'available': False,
                    'message': 'Technitium DNS not configured or unavailable'
                })
                return

            # Get DHCP scopes
            scopes_url = f"{TECHNITIUM_URL}/api/dhcp/scopes/list?token={token}"
            scopes_data = self.fetch_technitium_api(scopes_url)

            if not scopes_data or scopes_data.get('status') == 'error':
                self.send_json({
                    'available': False,
                    'message': scopes_data.get('errorMessage', 'Failed to get DHCP scopes')
                })
                return

            scopes = scopes_data.get('response', {}).get('scopes', [])
            all_leases = []
            scope_stats = []

            # Get all leases (single API call for all scopes)
            leases_url = f"{TECHNITIUM_URL}/api/dhcp/leases/list?token={token}"
            leases_data = self.fetch_technitium_api(leases_url)
            all_raw_leases = []
            if leases_data and leases_data.get('status') == 'ok':
                all_raw_leases = leases_data.get('response', {}).get('leases', [])

            for scope in scopes:
                scope_name = scope.get('name', 'unknown')

                # Filter leases for this scope
                leases = [l for l in all_raw_leases if l.get('scope') == scope_name]

                # Add scope info
                scope_stats.append({
                    'name': scope_name,
                    'enabled': scope.get('enabled', False),
                    'startAddress': scope.get('startingAddress', ''),
                    'endAddress': scope.get('endingAddress', ''),
                    'leaseCount': len(leases)
                })

                # Add leases with scope name (show all from this scope)
                for lease in leases:
                    all_leases.append({
                        'scope': scope_name,
                        'address': lease.get('address', ''),
                        'hostname': lease.get('hostName', ''),
                        'hardwareAddress': lease.get('hardwareAddress', ''),
                        'leaseExpires': lease.get('leaseExpires', ''),
                        'type': lease.get('type', '')
                    })

            # Calculate real total before truncation
            real_total = len(all_raw_leases)

            self.send_json({
                'available': True,
                'scopes': scope_stats,
                'leases': all_leases[:100],  # Display up to 100 leases
                'totalLeases': real_total,
                'displayedLeases': min(len(all_leases), 100)
            })
        except Exception as e:
            self.send_json({
                'available': False,
                'message': str(e)
            })

    def handle_fail2ban_status(self):
        """Get Fail2ban jail status and banned IPs"""
        try:
            # Find fail2ban-client
            f2b_client = None
            for path in ['/run/current-system/sw/bin/fail2ban-client', '/usr/bin/fail2ban-client', 'fail2ban-client']:
                try:
                    result = subprocess.run([path, '--version'], capture_output=True, timeout=2)
                    if result.returncode == 0:
                        f2b_client = path
                        break
                except:
                    continue

            if not f2b_client:
                self.send_json({
                    'available': False,
                    'message': 'fail2ban-client not found'
                })
                return

            if os.geteuid() == 0:
                status_cmd = [f2b_client, 'status']
                jail_cmd = lambda jail: [f2b_client, 'status', jail]
            else:
                # Find sudo wrapper (NixOS uses /run/wrappers/bin/sudo)
                sudo_cmd = '/run/wrappers/bin/sudo'
                if not os.path.exists(sudo_cmd):
                    sudo_cmd = 'sudo'
                status_cmd = [sudo_cmd, '-n', f2b_client, 'status']
                jail_cmd = lambda jail: [sudo_cmd, '-n', f2b_client, 'status', jail]

            # Get jail list
            result = subprocess.run(
                status_cmd,
                capture_output=True, text=True, timeout=5
            )

            if result.returncode != 0:
                self.send_json({
                    'available': False,
                    'message': result.stderr.strip() or result.stdout.strip() or 'Failed to get fail2ban status'
                })
                return

            # Parse jail list
            jails = []
            for line in result.stdout.split('\n'):
                if 'Jail list:' in line:
                    jail_names = line.split(':')[1].strip().split(', ')
                    jails = [j.strip() for j in jail_names if j.strip()]
                    break

            # Get status for each jail
            jail_stats = []
            total_banned = 0
            all_banned_ips = []

            for jail in jails:
                jail_result = subprocess.run(
                    jail_cmd(jail),
                    capture_output=True, text=True, timeout=5
                )

                if jail_result.returncode != 0:
                    continue

                stats = {
                    'name': jail,
                    'currentlyFailed': 0,
                    'totalFailed': 0,
                    'currentlyBanned': 0,
                    'totalBanned': 0,
                    'bannedIPs': []
                }

                for line in jail_result.stdout.split('\n'):
                    line = line.strip()
                    if 'Currently failed:' in line:
                        stats['currentlyFailed'] = int(line.split(':')[1].strip())
                    elif 'Total failed:' in line:
                        stats['totalFailed'] = int(line.split(':')[1].strip())
                    elif 'Currently banned:' in line:
                        stats['currentlyBanned'] = int(line.split(':')[1].strip())
                    elif 'Total banned:' in line:
                        stats['totalBanned'] = int(line.split(':')[1].strip())
                    elif 'Banned IP list:' in line:
                        ip_list = line.split(':')[1].strip()
                        if ip_list:
                            stats['bannedIPs'] = ip_list.split()
                            all_banned_ips.extend(stats['bannedIPs'])

                total_banned += stats['currentlyBanned']
                jail_stats.append(stats)

            self.send_json({
                'available': True,
                'jails': jail_stats,
                'totalCurrentlyBanned': total_banned,
                'allBannedIPs': list(set(all_banned_ips))
            })

        except Exception as e:
            self.send_json({
                'available': False,
                'message': str(e)
            })

    def handle_speedtest_run(self):
        """Start a speed test"""
        global SPEEDTEST_STATE

        if SPEEDTEST_STATE['running']:
            self.send_json({'error': 'Speed test already running'}, 400)
            return

        # Find speedtest-cli
        speedtest_cmd = None
        for path in ['/run/current-system/sw/bin/speedtest-cli', '/usr/bin/speedtest-cli', 'speedtest-cli']:
            try:
                result = subprocess.run([path, '--version'], capture_output=True, timeout=2)
                if result.returncode == 0:
                    speedtest_cmd = path
                    break
            except:
                continue

        if not speedtest_cmd:
            self.send_json({'error': 'speedtest-cli not found'}, 500)
            return

        # Reset state
        SPEEDTEST_STATE['running'] = True
        SPEEDTEST_STATE['stage'] = 'Initializing...'
        SPEEDTEST_STATE['progress'] = 0
        SPEEDTEST_STATE['result'] = None
        SPEEDTEST_STATE['error'] = None

        # Start speed test in background thread
        def run_speedtest():
            global SPEEDTEST_STATE
            try:
                SPEEDTEST_STATE['stage'] = 'Finding best server...'
                SPEEDTEST_STATE['progress'] = 10

                # Run speedtest-cli with JSON output
                result = subprocess.run(
                    [speedtest_cmd, '--json', '--secure'],
                    capture_output=True, text=True, timeout=120
                )

                if result.returncode != 0:
                    SPEEDTEST_STATE['error'] = result.stderr or 'Speed test failed'
                    SPEEDTEST_STATE['running'] = False
                    return

                # Parse JSON output
                data = json.loads(result.stdout)

                # Extract results (speedtest-cli outputs bits/second, convert to Mbps)
                download_mbps = data.get('download', 0) / 1_000_000
                upload_mbps = data.get('upload', 0) / 1_000_000
                ping_ms = data.get('ping', 0)

                # Get server info
                server = data.get('server', {})
                server_name = f"{server.get('name', 'Unknown')} ({server.get('sponsor', '')})"

                SPEEDTEST_STATE['result'] = {
                    'download': download_mbps,
                    'upload': upload_mbps,
                    'ping': ping_ms,
                    'server': server_name,
                    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
                }
                SPEEDTEST_STATE['progress'] = 100
                SPEEDTEST_STATE['stage'] = 'Complete'

            except subprocess.TimeoutExpired:
                SPEEDTEST_STATE['error'] = 'Speed test timed out'
            except json.JSONDecodeError as e:
                SPEEDTEST_STATE['error'] = f'Failed to parse results: {e}'
            except Exception as e:
                SPEEDTEST_STATE['error'] = str(e)
            finally:
                SPEEDTEST_STATE['running'] = False

        # Progress simulation thread (speedtest-cli doesn't give real-time progress)
        def simulate_progress():
            global SPEEDTEST_STATE
            stages = [
                (10, 'Finding best server...'),
                (20, 'Connecting to server...'),
                (30, 'Testing download speed...'),
                (50, 'Testing download speed...'),
                (70, 'Testing upload speed...'),
                (85, 'Testing upload speed...'),
                (95, 'Finalizing...')
            ]
            for progress, stage in stages:
                if not SPEEDTEST_STATE['running']:
                    break
                SPEEDTEST_STATE['progress'] = progress
                SPEEDTEST_STATE['stage'] = stage
                time.sleep(3)

        thread = threading.Thread(target=run_speedtest, daemon=True)
        progress_thread = threading.Thread(target=simulate_progress, daemon=True)
        SPEEDTEST_STATE['thread'] = thread
        thread.start()
        progress_thread.start()

        self.send_json({'status': 'started'})

    def handle_speedtest_status(self):
        """Get speed test status"""
        global SPEEDTEST_STATE

        self.send_json({
            'running': SPEEDTEST_STATE['running'],
            'stage': SPEEDTEST_STATE['stage'],
            'progress': SPEEDTEST_STATE['progress'],
            'result': SPEEDTEST_STATE['result'],
            'error': SPEEDTEST_STATE['error']
        })

    def handle_firewall_logs_recent(self, query):
        """Return recent firewall log lines"""
        limit = self.parse_positive_int(query.get('limit', ['30'])[0], default=30, minimum=1, maximum=200)

        try:
            logs = self.read_firewall_logs(limit=limit)
            self.send_json({
                'logs': logs,
                'count': len(logs)
            })
        except Exception as e:
            self.send_error_json(500, f'Failed to read firewall logs: {e}')

    def handle_firewall_logs_stream(self, query):
        """Stream firewall logs via Server-Sent Events"""
        limit = self.parse_positive_int(query.get('limit', ['20'])[0], default=20, minimum=0, maximum=100)

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

        try:
            initial_logs = self.read_firewall_logs(limit=limit)
            for entry in initial_logs:
                self.write_sse_event('log', entry)

            self.write_sse_event('ready', {'count': len(initial_logs)})

            process = subprocess.Popen(
                ['journalctl', '-k', '-f', '-n', '0', '-o', 'short-iso'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1
            )

            try:
                stdout = process.stdout
                if stdout is None:
                    self.write_sse_event('error', {'message': 'journalctl stream unavailable'})
                    return

                while True:
                    ready, _, _ = select.select([stdout], [], [], 15)
                    if ready:
                        line = stdout.readline()
                        if not line:
                            break

                        entry = self.parse_firewall_log_line(line)
                        if entry:
                            self.write_sse_event('log', entry)
                    else:
                        self.write_sse_event('heartbeat', {'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')})
            finally:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as e:
            try:
                self.write_sse_event('error', {'message': str(e)})
            except Exception:
                pass

    def handle_wol_wake(self):
        """Send a Wake-on-LAN magic packet"""
        if not WOL_DEVICES:
            self.send_error_json(403, 'Wake-on-LAN is not configured')
            return

        try:
            content_length = int(self.headers.get('Content-Length', '0'))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b'{}'
            payload = json.loads(raw_body.decode('utf-8'))
        except json.JSONDecodeError:
            self.send_error_json(400, 'Invalid JSON payload')
            return

        mac_address = str(payload.get('macAddress', '')).strip()
        if not self.is_valid_mac_address(mac_address):
            self.send_error_json(400, 'Invalid or missing macAddress')
            return

        device = self.find_wol_device(mac_address)
        if not device:
            self.send_error_json(403, 'Requested device is not allowed')
            return

        broadcast_address = str(device.get('broadcastAddress', '255.255.255.255')).strip() or '255.255.255.255'
        port = int(device.get('port', 9))

        try:
            self.send_magic_packet(mac_address, broadcast_address, port)
            self.send_json({
                'status': 'sent',
                'macAddress': mac_address,
                'broadcastAddress': broadcast_address,
                'port': port
            })
        except Exception as e:
            self.send_error_json(500, f'Failed to send magic packet: {e}')

    def get_technitium_token(self):
        """Get Technitium API token from file or cache"""
        global TECHNITIUM_TOKEN_CACHE

        # Check cache
        if TECHNITIUM_TOKEN_CACHE['token'] and time.time() < TECHNITIUM_TOKEN_CACHE['expires']:
            return TECHNITIUM_TOKEN_CACHE['token']

        # Read token from file
        if TECHNITIUM_API_KEY_FILE and os.path.exists(TECHNITIUM_API_KEY_FILE):
            try:
                with open(TECHNITIUM_API_KEY_FILE, 'r') as f:
                    token = f.read().strip()
                    if token:
                        # Cache for 25 minutes (Technitium default is 30 min)
                        TECHNITIUM_TOKEN_CACHE['token'] = token
                        TECHNITIUM_TOKEN_CACHE['expires'] = time.time() + 1500
                        return token
            except:
                pass

        return None

    def fetch_technitium_api(self, url):
        """Fetch data from Technitium API"""
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'RouterDashboard/1.0'})
            with urllib.request.urlopen(req, timeout=5) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as e:
            return {'status': 'error', 'errorMessage': f'HTTP {e.code}'}
        except urllib.error.URLError as e:
            return {'status': 'error', 'errorMessage': str(e.reason)}
        except Exception as e:
            return {'status': 'error', 'errorMessage': str(e)}

    def get_default_gateway(self):
        """Get the default gateway IP"""
        try:
            result = subprocess.run(
                ['ip', 'route', 'show', 'default'],
                capture_output=True, text=True, timeout=2
            )
            # Parse: "default via 192.168.1.1 dev eth0"
            for part in result.stdout.split():
                if re.match(r'\d+\.\d+\.\d+\.\d+', part):
                    return part
        except:
            pass
        return None

    def parse_positive_int(self, value, default=0, minimum=0, maximum=None):
        """Parse positive integer query parameter safely"""
        try:
            result = int(value)
        except (TypeError, ValueError):
            return default

        if result < minimum:
            return default
        if maximum is not None and result > maximum:
            return maximum
        return result

    def sum_numeric_values(self, *values):
        """Sum numeric values from scalars or lists"""
        total = 0
        for value in values:
            if value is None:
                continue
            if isinstance(value, list):
                total += sum(v for v in value if isinstance(v, (int, float)))
            elif isinstance(value, (int, float)):
                total += value
        return total

    def get_service_status(self, systemctl, service):
        """Resolve and return status for a systemd unit name"""
        candidates = [service]
        if not service.endswith('.service'):
            candidates.append(f'{service}.service')

        for candidate in candidates:
            try:
                result = subprocess.run(
                    [systemctl, 'show', candidate, '--property=Id,ActiveState,LoadState', '--value'],
                    capture_output=True, text=True, timeout=3,
                    env={**os.environ, 'DBUS_SESSION_BUS_ADDRESS': ''}
                )

                if result.returncode != 0:
                    continue

                values = result.stdout.strip().splitlines()
                if len(values) < 3:
                    continue

                unit_id, active_state, load_state = values[:3]
                if load_state == 'not-found':
                    continue

                return {
                    'name': service,
                    'unit': unit_id or candidate,
                    'status': active_state or 'unknown',
                    'active': active_state == 'active'
                }
            except Exception:
                continue

        return {
            'name': service,
            'unit': '',
            'status': 'not-found',
            'active': False
        }

    def read_firewall_logs(self, limit=30):
        """Read recent firewall logs from the kernel journal"""
        result = subprocess.run(
            ['journalctl', '-k', '-n', str(limit * 5), '-o', 'short-iso', '--no-pager'],
            capture_output=True, text=True, timeout=5
        )

        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or 'journalctl failed')

        logs = []
        for line in result.stdout.splitlines():
            entry = self.parse_firewall_log_line(line)
            if entry:
                logs.append(entry)

        return logs[-limit:]

    def parse_firewall_log_line(self, line):
        """Parse a kernel journal line into structured firewall log data"""
        if 'FW-' not in line:
            return None

        raw = line.strip()
        prefix_match = re.search(r'(FW-[A-Z-]+)', raw)
        prefix = prefix_match.group(1) if prefix_match else 'FW-LOG'

        fields = {}
        for key in ['IN', 'OUT', 'MAC', 'SRC', 'DST', 'LEN', 'TOS', 'PREC', 'TTL',
                    'ID', 'DF', 'PROTO', 'SPT', 'DPT', 'WINDOW', 'RES', 'SYN',
                    'URGP', 'MARK']:
            match = re.search(rf'\b{key}=([^\s]+)', raw)
            if match:
                fields[key] = match.group(1)

        action = prefix.replace('FW-', '').replace('-', ' ').title()
        proto = fields.get('PROTO', '--')
        src = fields.get('SRC', '--')
        dst = fields.get('DST', '--')

        summary = f'{action}: {proto} {src}'
        if 'SPT' in fields:
            summary += f':{fields["SPT"]}'
        summary += f' -> {dst}'
        if 'DPT' in fields:
            summary += f':{fields["DPT"]}'

        timestamp_match = re.match(r'^(\S+\s+\S+)\s+', raw)

        return {
            'timestamp': timestamp_match.group(1) if timestamp_match else '',
            'prefix': prefix,
            'action': action,
            'summary': summary,
            'raw': raw,
            'interfaceIn': fields.get('IN', ''),
            'interfaceOut': fields.get('OUT', ''),
            'protocol': proto,
            'src': src,
            'srcPort': fields.get('SPT'),
            'dst': dst,
            'dstPort': fields.get('DPT')
        }

    def write_sse_event(self, event_name, payload):
        """Write a single SSE event to the client"""
        body = json.dumps(payload)
        self.wfile.write(f'event: {event_name}\n'.encode())
        self.wfile.write(f'data: {body}\n\n'.encode())
        self.wfile.flush()

    def is_valid_mac_address(self, value):
        """Validate MAC address format"""
        return bool(re.fullmatch(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}', value))

    def normalize_mac_address(self, value):
        """Normalize MAC address for comparisons"""
        return value.replace('-', ':').upper()

    def find_wol_device(self, mac_address):
        """Return configured Wake-on-LAN device by MAC address"""
        normalized_mac = self.normalize_mac_address(mac_address)
        for device in WOL_DEVICES:
            configured_mac = str(device.get('macAddress', ''))
            if self.is_valid_mac_address(configured_mac) and self.normalize_mac_address(configured_mac) == normalized_mac:
                return device
        return None

    def send_magic_packet(self, mac_address, broadcast_address, port):
        """Send a Wake-on-LAN magic packet over UDP broadcast"""
        mac_hex = self.normalize_mac_address(mac_address).replace(':', '')
        payload = bytes.fromhex('FF' * 6 + mac_hex * 16)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.sendto(payload, (broadcast_address, port))
        finally:
            sock.close()

    # === Helper Methods ===

    def read_file(self, path):
        """Read file contents safely"""
        try:
            with open(path, 'r') as f:
                return f.read()
        except:
            return ''

    def get_uptime(self):
        """Get human-readable uptime"""
        try:
            uptime_secs = float(self.read_file('/proc/uptime').split()[0])
            days = int(uptime_secs // 86400)
            hours = int((uptime_secs % 86400) // 3600)
            minutes = int((uptime_secs % 3600) // 60)
            return f"up {days}d {hours}h {minutes}m"
        except:
            return 'unknown'

    def parse_meminfo(self):
        """Parse /proc/meminfo into dict"""
        result = {}
        try:
            for line in self.read_file('/proc/meminfo').split('\n'):
                if ':' in line:
                    key, value = line.split(':')
                    # Convert kB to bytes
                    value = value.strip().replace(' kB', '')
                    result[key.strip()] = int(value) * 1024
        except:
            pass
        return result

    def get_cpu_usage(self):
        """Calculate CPU usage percentage"""
        try:
            # Read current stats
            with open('/proc/stat', 'r') as f:
                line = f.readline()

            parts = line.split()
            # user, nice, system, idle, iowait, irq, softirq, steal
            idle = int(parts[4])
            total = sum(int(p) for p in parts[1:8])

            # Get previous values
            prev_idle = getattr(self, '_prev_cpu_idle', idle)
            prev_total = getattr(self, '_prev_cpu_total', total)

            # Calculate
            diff_idle = idle - prev_idle
            diff_total = total - prev_total

            # Store for next time
            self._prev_cpu_idle = idle
            self._prev_cpu_total = total

            if diff_total == 0:
                return 0.0

            return (1.0 - diff_idle / diff_total) * 100
        except:
            return 0.0

    def get_disk_usage(self, path):
        """Get disk usage percentage for a path"""
        try:
            stat = os.statvfs(path)
            total = stat.f_blocks * stat.f_frsize
            free = stat.f_bfree * stat.f_frsize
            used = total - free
            return (used / total * 100) if total > 0 else 0
        except:
            return 0

    def get_disk_usage_detailed(self, path):
        """Get disk usage with absolute values"""
        try:
            stat = os.statvfs(path)
            total = stat.f_blocks * stat.f_frsize
            free = stat.f_bfree * stat.f_frsize
            used = total - free
            percent = (used / total * 100) if total > 0 else 0
            return percent, used, total
        except:
            return 0, 0, 0

    def format_bytes(self, bytes_val):
        """Format bytes to human readable string"""
        if bytes_val == 0:
            return "0 B"
        units = ['B', 'KB', 'MB', 'GB', 'TB']
        i = 0
        val = float(bytes_val)
        while val >= 1024 and i < len(units) - 1:
            val /= 1024
            i += 1
        return f"{val:.1f} {units[i]}"

    def get_ipv4(self, interface):
        """Get IPv4 address for interface"""
        try:
            result = subprocess.run(
                ['ip', '-4', 'addr', 'show', interface],
                capture_output=True, text=True, timeout=2
            )
            match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result.stdout)
            return match.group(1) if match else 'N/A'
        except:
            return 'N/A'

    def get_ipv6(self, interface):
        """Get IPv6 addresses for interface (global scope only)"""
        try:
            result = subprocess.run(
                ['ip', '-6', 'addr', 'show', interface, 'scope', 'global'],
                capture_output=True, text=True, timeout=2
            )
            # Find all global IPv6 addresses
            addresses = re.findall(r'inet6 ([0-9a-f:]+)', result.stdout)
            return addresses if addresses else []
        except:
            return []

    def calculate_rates(self, interface, rx_bytes, tx_bytes):
        """Calculate RX/TX rates based on previous readings"""
        global RATE_CACHE, RATE_CACHE_TIME

        now = time.time()
        rx_rate = 0
        tx_rate = 0

        cache_key = interface
        if cache_key in RATE_CACHE:
            prev_rx, prev_tx = RATE_CACHE[cache_key]
            prev_time = RATE_CACHE_TIME[cache_key]
            time_diff = now - prev_time

            if time_diff > 0:
                rx_rate = max(0, (rx_bytes - prev_rx) / time_diff)
                tx_rate = max(0, (tx_bytes - prev_tx) / time_diff)

        RATE_CACHE[cache_key] = (rx_bytes, tx_bytes)
        RATE_CACHE_TIME[cache_key] = now

        return int(rx_rate), int(tx_rate)


def run_server():
    """Start the HTTP server"""
    handler = RouterAPIHandler

    class ThreadingHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
        allow_reuse_address = True
        daemon_threads = True

    with ThreadingHTTPServer((BIND, PORT), handler) as httpd:
        print(f"Router Dashboard serving on http://{BIND}:{PORT}")
        print(f"Static files from: {STATIC_DIR}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == '__main__':
    run_server()
