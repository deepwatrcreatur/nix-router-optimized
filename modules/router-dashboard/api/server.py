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
import shlex
import socket
import time
import urllib.request
import urllib.error
import threading
import select
from pathlib import Path
from tempfile import NamedTemporaryFile
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
    DASHBOARD_VPNS = json.loads(os.environ.get('DASHBOARD_VPNS', '[]'))
except json.JSONDecodeError:
    DASHBOARD_VPNS = []
try:
    DASHBOARD_TUNNELS = json.loads(os.environ.get('DASHBOARD_TUNNELS', '[]'))
except json.JSONDecodeError:
    DASHBOARD_TUNNELS = []
try:
    DASHBOARD_REMOTE_ADMIN = json.loads(os.environ.get('DASHBOARD_REMOTE_ADMIN', '[]'))
except json.JSONDecodeError:
    DASHBOARD_REMOTE_ADMIN = []
try:
    DASHBOARD_INTERFACES = json.loads(os.environ.get('DASHBOARD_INTERFACES', '[]'))
except json.JSONDecodeError:
    DASHBOARD_INTERFACES = []
try:
    WOL_DEVICES = json.loads(os.environ.get('DASHBOARD_WOL_DEVICES', '[]'))
except json.JSONDecodeError:
    WOL_DEVICES = []

NAT64_PREFIX = os.environ.get('DASHBOARD_NAT64_PREFIX', '')
NAT64_POOL = os.environ.get('DASHBOARD_NAT64_POOL', '')

# Rate tracking for interface stats
RATE_CACHE = {}
RATE_CACHE_TIME = {}
CPU_CACHE = {
    'idle': None,
    'total': None,
    'usage': 0.0,
    'timestamp': 0.0
}
SYSTEM_INFO_CACHE = {
    'data': None,
    'timestamp': 0.0
}
CADDY_DNS_CACHE = {
    'data': None,
    'timestamp': 0.0,
    'signature': None
}

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
        elif path == '/api/system/info':
            self.handle_system_info()
        elif path == '/api/interfaces/stats':
            self.handle_interface_stats()
        elif path == '/api/connections/summary':
            self.handle_connections_summary()
        elif path == '/api/connections/top':
            self.handle_connections_top(query)
        elif path == '/api/services/status':
            self.handle_services_status()
        elif path == '/api/vpn/status':
            self.handle_vpn_status()
        elif path == '/api/tunnels/status':
            self.handle_tunnels_status()
        elif path == '/api/remote-admin/status':
            self.handle_remote_admin_status()
        elif path == '/api/caddy/status':
            self.handle_caddy_status()
        elif path == '/api/service/logs':
            self.handle_service_logs(query)
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
        elif path == '/api/nat64/connections':
            self.handle_nat64_connections()
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

            # Expose configured interfaces by both their real device names and
            # stable dashboard role aliases. When multiple interfaces share a
            # role (for example LAN + VLAN subinterfaces), prefer the
            # non-VLAN device for the role alias and always keep the device
            # entry so the frontend can address exact NIC names directly.
            iface_map = {}
            role_candidates = {}
            for iface in DASHBOARD_INTERFACES:
                device = iface.get('device')
                role = iface.get('role')
                if device:
                    iface_map[device] = device
                if device and role:
                    current = role_candidates.get(role)
                    if current is None or self.prefer_interface_alias(device, current):
                        role_candidates[role] = device

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

                stats = {
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

                interfaces[name] = stats

            for role, device in role_candidates.items():
                if device in interfaces:
                    interfaces[role] = interfaces[device]

            self.send_json(interfaces)
        except Exception as e:
            self.send_error_json(500, str(e))

    def prefer_interface_alias(self, candidate, current):
        """Prefer physical base interfaces over VLAN subinterfaces for role aliases."""
        if current == candidate:
            return False
        candidate_is_vlan = '.' in candidate
        current_is_vlan = '.' in current
        if candidate_is_vlan != current_is_vlan:
            return not candidate_is_vlan
        return candidate < current

    def handle_system_info(self):
        """Static-ish host information for the system info widget"""
        try:
            self.send_json(self.get_system_info())
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

    def handle_vpn_status(self):
        """Declarative VPN status from router module metadata"""
        systemctl = self.find_systemctl()
        vpns = []

        for entry in DASHBOARD_VPNS:
            vpns.append(self.get_vpn_entry_status(systemctl, entry))

        active_count = len([vpn for vpn in vpns if vpn.get('status') == 'up'])
        warning_count = len([vpn for vpn in vpns if vpn.get('status') == 'warning'])
        down_count = len([vpn for vpn in vpns if vpn.get('status') == 'down'])

        self.send_json({
            'configured': len(vpns),
            'active': active_count,
            'warning': warning_count,
            'down': down_count,
            'vpns': vpns
        })

    def get_vpn_entry_status(self, systemctl, entry):
        """Build one VPN runtime status row from declarative metadata"""
        kind = entry.get('kind', 'unknown')
        name = entry.get('name') or kind
        unit = entry.get('unit') or ''
        interface = entry.get('interface')

        service = self.get_service_status(systemctl, unit) if systemctl and unit else {
            'name': unit,
            'unit': unit,
            'status': 'unknown',
            'active': False
        }
        interface_status = self.get_interface_status(interface) if interface else None
        details = self.get_vpn_details(kind, interface)

        service_active = service.get('active', False)
        interface_up = interface_status is None or interface_status.get('state') in ('UP', 'UNKNOWN')
        status = 'up' if service_active and interface_up else 'down'
        if service_active and not interface_up:
            status = 'warning'

        return {
            'kind': kind,
            'name': name,
            'unit': service.get('unit') or unit,
            'service': service,
            'interface': interface_status,
            'status': status,
            'details': details
        }

    def handle_tunnels_status(self):
        """Declarative tunnels status from router module metadata"""
        systemctl = self.find_systemctl()
        tunnels = []

        for entry in DASHBOARD_TUNNELS:
            tunnels.append(self.get_tunnel_entry_status(systemctl, entry))

        active_count = len([t for t in tunnels if t.get('status') == 'up'])
        warning_count = len([t for t in tunnels if t.get('status') == 'warning'])
        down_count = len([t for t in tunnels if t.get('status') == 'down'])

        self.send_json({
            'configured': len(tunnels),
            'active': active_count,
            'warning': warning_count,
            'down': down_count,
            'tunnels': tunnels
        })

    def get_tunnel_entry_status(self, systemctl, entry):
        """Build one tunnel runtime status row from declarative metadata"""
        provider = entry.get('provider') or 'other'
        name = entry.get('name') or provider
        unit = entry.get('unit') or ''
        public_url = entry.get('publicUrl') or ''
        description = entry.get('description') or ''

        service = self.get_service_status(systemctl, unit) if systemctl and unit else {
            'name': unit,
            'unit': unit,
            'status': 'unknown',
            'active': False
        }

        service_status = service.get('status', 'unknown')
        service_active = service.get('active', False)

        if service_active and service_status == 'active' and public_url:
            status = 'up'
        elif service_active:
            status = 'warning'
        else:
            status = 'down'

        return {
            'provider': provider,
            'name': name,
            'unit': service.get('unit') or unit,
            'publicUrl': public_url,
            'service': service,
            'status': status,
            'details': {
                'description': description,
                'publicUrl': public_url
            }
        }

    def handle_remote_admin_status(self):
        """Declarative remote administration status from router module metadata"""
        systemctl = self.find_systemctl()
        entries = []

        for entry in DASHBOARD_REMOTE_ADMIN:
            entries.append(self.get_remote_admin_entry_status(systemctl, entry))

        active_count = len([e for e in entries if e.get('status') == 'up'])
        warning_count = len([e for e in entries if e.get('status') == 'warning'])
        down_count = len([e for e in entries if e.get('status') == 'down'])

        self.send_json({
            'configured': len(entries),
            'active': active_count,
            'warning': warning_count,
            'down': down_count,
            'entries': entries
        })

    def get_remote_admin_entry_status(self, systemctl, entry):
        """Build one remote admin runtime status row from declarative metadata"""
        kind = entry.get('kind') or 'other'
        name = entry.get('name') or kind
        unit = entry.get('unit') or ''
        url = entry.get('url') or ''
        description = entry.get('description') or ''

        service = self.get_service_status(systemctl, unit) if systemctl and unit else {
            'name': unit,
            'unit': unit,
            'status': 'unknown',
            'active': False
        }

        service_status = service.get('status', 'unknown')
        service_active = service.get('active', False)

        if service_active and service_status == 'active' and url:
            status = 'up'
        elif service_active:
            status = 'warning'
        else:
            status = 'down'

        return {
            'kind': kind,
            'name': name,
            'unit': service.get('unit') or unit,
            'url': url,
            'service': service,
            'status': status,
            'details': {
                'description': description,
                'url': url
            }
        }

    def get_interface_status(self, interface):
        """Return a small interface status object without failing missing devices"""
        if not interface:
            return None

        iface_path = Path('/sys/class/net') / interface
        if not iface_path.exists():
            return {
                'name': interface,
                'state': 'missing',
                'ipv4': '',
                'ipv6': []
            }

        return {
            'name': interface,
            'state': (self.read_file(iface_path / 'operstate').strip() or 'unknown').upper(),
            'ipv4': self.get_ipv4(interface),
            'ipv6': self.get_ipv6(interface)
        }

    def get_vpn_details(self, kind, interface):
        """Return best-effort VPN-specific counters"""
        if kind == 'wireguard' and interface:
            return self.get_wireguard_details(interface)
        if kind == 'tailscale':
            return self.get_tailscale_details()
        return {}

    def get_wireguard_details(self, interface):
        """Use wg dump for peer count and latest handshake when available"""
        wg = self.find_executable(['/run/current-system/sw/bin/wg', '/usr/bin/wg', 'wg'], ['help'])
        if not wg:
            return {'available': False, 'message': 'wg command unavailable'}

        try:
            result = subprocess.run(
                [wg, 'show', interface, 'dump'],
                capture_output=True, text=True, timeout=3
            )
        except Exception as exc:
            return {'available': False, 'message': str(exc)}

        if result.returncode != 0:
            return {
                'available': False,
                'message': (result.stderr or result.stdout).strip() or 'wg dump failed'
            }

        lines = [line for line in result.stdout.splitlines() if line.strip()]
        peer_lines = lines[1:] if lines else []
        handshakes = []
        for line in peer_lines:
            fields = line.split('\t')
            if len(fields) >= 5:
                try:
                    timestamp = int(fields[4])
                    if timestamp > 0:
                        handshakes.append(timestamp)
                except ValueError:
                    pass

        return {
            'available': True,
            'peerCount': len(peer_lines),
            'latestHandshake': max(handshakes) if handshakes else None
        }

    def get_tailscale_details(self):
        """Use tailscale status json when available"""
        tailscale = self.find_executable(
            ['/run/current-system/sw/bin/tailscale', '/usr/bin/tailscale', 'tailscale'],
            ['version']
        )
        if not tailscale:
            return {'available': False, 'message': 'tailscale command unavailable'}

        try:
            result = subprocess.run(
                [tailscale, 'status', '--json'],
                capture_output=True, text=True, timeout=4
            )
        except Exception as exc:
            return {'available': False, 'message': str(exc)}

        if result.returncode != 0:
            return {
                'available': False,
                'message': (result.stderr or result.stdout).strip() or 'tailscale status failed'
            }

        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            return {'available': False, 'message': 'tailscale returned invalid JSON'}

        peers = data.get('Peer') or {}
        return {
            'available': True,
            'backendState': data.get('BackendState', 'unknown'),
            'peerCount': len(peers)
        }

    def handle_caddy_status(self):
        """Detailed Caddy diagnostics"""
        systemctl = self.find_systemctl()
        if not systemctl:
            self.send_json({
                'available': False,
                'message': 'systemctl not found'
            })
            return

        properties = self.get_unit_properties(systemctl, 'caddy', [
            'Id',
            'ActiveState',
            'SubState',
            'Result',
            'ExecMainStatus',
            'ExecStartPre',
            'EnvironmentFiles',
            'ExecStart'
        ])        
        caddy_bin = self.find_executable([
            '/run/current-system/sw/bin/caddy',
            '/usr/bin/caddy',
            'caddy'
        ], [ 'version' ]) or self.extract_exec_path(properties.get('ExecStart', ''))
        env_file = '/run/caddy/caddy.env'
        token_file = '/run/agenix/cloudflare-api-key'
        env_configured = '/run/caddy/caddy.env' in properties.get('EnvironmentFiles', '')
        env_present = env_configured or os.path.exists(env_file)
        token_exists = os.path.exists(token_file)
        token_value = ''
        if token_exists:
            token_value = self.read_file(token_file).strip()
        live_config = None

        config_valid = False
        config_message = 'caddy binary not found'
        if properties.get('ActiveState') == 'active':
            config_valid, config_message = self.check_live_caddy_admin_config()
            live_config = self.fetch_live_caddy_admin_config()
        elif caddy_bin:
            try:
                validate_env = dict(os.environ)
                if env_present:
                    validate_env.update(self.read_env_file(env_file))
                elif token_value:
                    validate_env['CLOUDFLARE_API_TOKEN'] = token_value

                config_valid, config_message = self.validate_caddy_config(caddy_bin, validate_env)
            except Exception as exc:
                config_message = str(exc)

        logs = self.read_service_logs('caddy', 25)
        recent_logs = self.get_recent_caddy_logs(logs)
        latest_error = self.get_latest_caddy_error(logs)
        message = latest_error or config_message
        dns_status = self.get_caddy_dns_status(live_config, token_value)
        if properties.get('ActiveState') == 'active' and not latest_error:
            if config_valid:
                message = 'Caddy is running and the current config is healthy'
            elif 'permission denied' in config_message.lower() and '/var/log/caddy/' in config_message:
                message = 'Caddy is running; offline validation is blocked by log-file permissions'

        self.send_json({
            'available': True,
            'unit': properties.get('Id', 'caddy.service'),
            'activeState': properties.get('ActiveState', 'unknown'),
            'subState': properties.get('SubState', 'unknown'),
            'result': properties.get('Result', 'unknown'),
            'active': properties.get('ActiveState') == 'active',
            'configValid': config_valid,
            'configMessage': config_message,
            'environmentFile': {
                'path': env_file,
                'configured': env_configured,
                'present': env_present
            },
            'cloudflareToken': {
                'path': token_file,
                'exists': token_exists,
                'usableForValidation': bool(token_value)
            },
            'dnsStatus': dns_status,
            'message': message,
            'logs': recent_logs[-12:]
        })

    def check_live_caddy_admin_config(self):
        """Use the local admin API as the source of truth for the running Caddy instance."""
        try:
            with urllib.request.urlopen('http://127.0.0.1:2019/config/', timeout=3) as response:
                if response.status == 200:
                    return True, 'Live Caddy admin config loaded successfully'
                return False, f'Caddy admin API returned HTTP {response.status}'
        except Exception as exc:
            return False, f'Unable to read live Caddy admin config: {exc}'

    def fetch_live_caddy_admin_config(self):
        """Fetch the live Caddy admin config JSON."""
        try:
            with urllib.request.urlopen('http://127.0.0.1:2019/config/', timeout=3) as response:
                if response.status != 200:
                    return None
                return json.loads(response.read().decode())
        except Exception:
            return None

    def get_caddy_dns_status(self, live_config, token_value):
        """Compare managed Cloudflare records with the current WAN IPs."""
        dynamic_dns = ((live_config.get('apps') or {}).get('dynamic_dns') or {}) if live_config else {}
        domains_by_zone = dynamic_dns.get('domains') or {}
        cache_signature = json.dumps(domains_by_zone, sort_keys=True)
        cache_age = time.time() - CADDY_DNS_CACHE['timestamp']
        if (
            CADDY_DNS_CACHE['data'] is not None
            and cache_age < 60
            and CADDY_DNS_CACHE['signature'] == cache_signature
        ):
            return CADDY_DNS_CACHE['data']

        if not live_config:
            data = {
                'available': False,
                'message': 'Live Caddy admin config unavailable',
                'domains': []
            }
            CADDY_DNS_CACHE['data'] = data
            CADDY_DNS_CACHE['timestamp'] = time.time()
            CADDY_DNS_CACHE['signature'] = cache_signature
            return data

        if not domains_by_zone:
            data = {
                'available': False,
                'message': 'Caddy dynamic DNS is not configured',
                'domains': []
            }
            CADDY_DNS_CACHE['data'] = data
            CADDY_DNS_CACHE['timestamp'] = time.time()
            CADDY_DNS_CACHE['signature'] = cache_signature
            return data

        if not token_value:
            data = {
                'available': False,
                'message': 'Cloudflare API token unavailable to dashboard',
                'domains': []
            }
            CADDY_DNS_CACHE['data'] = data
            CADDY_DNS_CACHE['timestamp'] = time.time()
            CADDY_DNS_CACHE['signature'] = cache_signature
            return data

        wan_iface = self.get_default_route_interface()
        wan_ipv4 = self.get_ipv4(wan_iface) if wan_iface else ''
        wan_ipv6 = self.get_ipv6(wan_iface) if wan_iface else []

        all_domains = []
        for zone_name, labels in domains_by_zone.items():
            zone_id = self.get_cloudflare_zone_id(token_value, zone_name)
            if not zone_id:
                for label in labels:
                    fqdn = zone_name if label == '@' else f'{label}.{zone_name}'
                    all_domains.append({
                        'name': fqdn,
                        'status': 'zone-missing',
                        'records': [],
                        'expectedIpv4': wan_ipv4,
                        'expectedIpv6': wan_ipv6
                    })
                continue

            records = self.get_cloudflare_zone_records(token_value, zone_id)
            by_name = {}
            for record in records:
                by_name.setdefault(record.get('name', ''), []).append(record)

            for label in labels:
                fqdn = zone_name if label == '@' else f'{label}.{zone_name}'
                domain_records = by_name.get(fqdn, [])
                ipv4_ok, ipv6_ok, status = self.evaluate_cloudflare_record_status(
                    fqdn,
                    by_name,
                    wan_ipv4,
                    wan_ipv6
                )

                all_domains.append({
                    'name': fqdn,
                    'status': status,
                    'records': [
                        {
                            'type': record.get('type'),
                            'content': record.get('content'),
                            'proxied': record.get('proxied', False)
                        }
                        for record in domain_records
                    ],
                    'expectedIpv4': wan_ipv4,
                    'expectedIpv6': wan_ipv6
                })

        data = {
            'available': True,
            'message': 'Managed Cloudflare records compared with current WAN IPs',
            'wanIpv4': wan_ipv4,
            'wanIpv6': wan_ipv6,
            'domains': all_domains
        }
        CADDY_DNS_CACHE['data'] = data
        CADDY_DNS_CACHE['timestamp'] = time.time()
        CADDY_DNS_CACHE['signature'] = cache_signature
        return data

    def evaluate_cloudflare_record_status(self, name, by_name, wan_ipv4, wan_ipv6, seen=None):
        if seen is None:
            seen = set()

        normalized_name = name.rstrip('.')
        if normalized_name in seen:
            return False, False, 'stale'
        seen.add(normalized_name)

        records = by_name.get(normalized_name, [])
        if not records:
            return False, False, 'missing'

        ipv4_records = [r.get('content') for r in records if r.get('type') == 'A']
        ipv6_records = [r.get('content') for r in records if r.get('type') == 'AAAA']

        ipv4_ok = (not wan_ipv4) or (wan_ipv4 in ipv4_records)
        ipv6_ok = (not wan_ipv6) or all(ip in ipv6_records for ip in wan_ipv6)

        if ipv4_records or ipv6_records:
            if ipv4_ok and ipv6_ok:
                return ipv4_ok, ipv6_ok, 'current'
            if ipv4_ok or ipv6_ok:
                return ipv4_ok, ipv6_ok, 'partial'
            return ipv4_ok, ipv6_ok, 'stale'

        cname_records = [r.get('content', '').rstrip('.') for r in records if r.get('type') == 'CNAME']
        if cname_records:
            best_status = 'stale'
            best_ipv4 = False
            best_ipv6 = False
            rank = {'current': 3, 'partial': 2, 'stale': 1, 'missing': 0}
            for target in cname_records:
                target_ipv4_ok, target_ipv6_ok, target_status = self.evaluate_cloudflare_record_status(
                    target,
                    by_name,
                    wan_ipv4,
                    wan_ipv6,
                    seen.copy()
                )
                if rank.get(target_status, -1) > rank.get(best_status, -1):
                    best_status = target_status
                    best_ipv4 = target_ipv4_ok
                    best_ipv6 = target_ipv6_ok
            return best_ipv4, best_ipv6, best_status

        return False, False, 'stale'

    def get_cloudflare_zone_id(self, token, zone_name):
        response = self.cloudflare_api_get(token, f'/zones?name={urlencode({"name": zone_name}).split("=", 1)[1]}')
        results = response.get('result') or []
        return results[0].get('id') if results else None

    def get_cloudflare_zone_records(self, token, zone_id):
        response = self.cloudflare_api_get(token, f'/zones/{zone_id}/dns_records?per_page=200')
        return response.get('result') or []

    def cloudflare_api_get(self, token, path):
        request = urllib.request.Request(
            f'https://api.cloudflare.com/client/v4{path}',
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json'
            }
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read().decode())

    def get_default_route_interface(self):
        try:
            result = subprocess.run(
                ['ip', 'route', 'show', 'default'],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode != 0:
                return ''
            parts = result.stdout.split()
            if 'dev' in parts:
                return parts[parts.index('dev') + 1]
        except Exception:
            pass
        return ''

    def get_system_info(self):
        """Return cached system identity information."""
        global SYSTEM_INFO_CACHE

        now = time.time()
        if SYSTEM_INFO_CACHE['data'] is not None and (now - SYSTEM_INFO_CACHE['timestamp']) < 300:
            return SYSTEM_INFO_CACHE['data']

        hostname = self.read_file('/proc/sys/kernel/hostname').strip() or 'unknown'
        os_release = self.parse_os_release()
        meminfo = self.parse_meminfo()
        default_iface = self.get_default_route_interface()
        generation = self.get_current_generation()
        root_total = self.get_disk_usage_detailed('/')[2]

        data = {
            'hostname': hostname,
            'os': os_release.get('PRETTY_NAME') or os_release.get('NAME') or 'NixOS',
            'kernel': self.read_file('/proc/sys/kernel/osrelease').strip() or 'unknown',
            'uptime': self.get_uptime(),
            'virtualization': self.detect_virtualization(),
            'cpuModel': self.get_cpu_model(),
            'cpuCores': os.cpu_count() or 0,
            'memoryTotal': meminfo.get('MemTotal', 0),
            'memoryTotalHuman': self.format_bytes(meminfo.get('MemTotal', 0)),
            'swapTotal': meminfo.get('SwapTotal', 0),
            'swapTotalHuman': self.format_bytes(meminfo.get('SwapTotal', 0)),
            'rootTotal': root_total,
            'rootTotalHuman': self.format_bytes(root_total),
            'defaultInterface': default_iface,
            'defaultIpv4': self.get_ipv4(default_iface) if default_iface else 'N/A',
            'defaultIpv6': self.get_ipv6(default_iface) if default_iface else [],
            'nixosVersion': self.get_nixos_version(),
            'systemGeneration': generation.get('label', 'unknown'),
            'systemPath': generation.get('path', ''),
            'bootedAt': self.get_boot_time_iso()
        }

        SYSTEM_INFO_CACHE['data'] = data
        SYSTEM_INFO_CACHE['timestamp'] = now
        return data

    def validate_caddy_config(self, caddy_bin, validate_env):
        """Validate the live Caddy config without requiring writable runtime log targets"""
        config_path = '/etc/caddy/caddy_config'
        adapt = subprocess.run(
            [caddy_bin, 'adapt', '--config', config_path, '--adapter', 'caddyfile'],
            capture_output=True,
            text=True,
            timeout=10,
            env=validate_env
        )
        if adapt.returncode != 0:
            message = (adapt.stderr or adapt.stdout).strip() or 'caddy adapt failed'
            return False, message

        adapted_json = (adapt.stdout or '').strip()
        if not adapted_json:
            return False, 'caddy adapt returned no JSON output'

        try:
            config = json.loads(adapted_json)
        except json.JSONDecodeError as exc:
            return False, f'Adapted JSON was invalid: {exc}'

        logging_cfg = config.get('logging', {}).get('logs', {})
        patched_logs = {}
        for name, log_cfg in logging_cfg.items():
            if isinstance(log_cfg, dict) and log_cfg.get('writer', {}).get('output') == 'file':
                patched = dict(log_cfg)
                patched['writer'] = {'output': 'discard'}
                patched_logs[name] = patched
            else:
                patched_logs[name] = log_cfg
        if logging_cfg:
            config.setdefault('logging', {})['logs'] = patched_logs

        with NamedTemporaryFile('w', delete=False, suffix='.json') as temp_config:
            json.dump(config, temp_config)
            temp_path = temp_config.name

        try:
            validate = subprocess.run(
                [caddy_bin, 'validate', '--config', temp_path],
                capture_output=True,
                text=True,
                timeout=10,
                env=validate_env
            )
        finally:
            try:
                os.unlink(temp_path)
            except OSError:
                pass

        config_valid = validate.returncode == 0
        message = (validate.stderr or validate.stdout).strip() or ('Config is valid' if config_valid else 'Validation failed')
        return config_valid, message

    def get_latest_caddy_error(self, logs):
        """Ignore stale errors that happened before the most recent successful start/reload."""
        success_markers = ('Started Caddy.', 'Reloaded Caddy.')
        relevant_logs = self.get_recent_caddy_logs(logs, success_markers)

        for line in reversed(relevant_logs):
            lowered = line.lower()
            if 'error' in lowered or 'fail' in lowered or 'permission denied' in lowered:
                return line
        return ''

    def get_recent_caddy_logs(self, logs, success_markers=('Started Caddy.', 'Reloaded Caddy.')):
        """Return only log lines from the most recent successful start/reload onward."""
        for index in range(len(logs) - 1, -1, -1):
            if any(marker in logs[index] for marker in success_markers):
                return logs[index:]
        return logs

    def handle_service_logs(self, query):
        """Generic service journal endpoint for dashboard detail pages"""
        unit = (query.get('unit') or [''])[0].strip()
        if not unit:
            self.send_error_json(400, 'Missing unit')
            return

        lines = self.parse_positive_int((query.get('lines') or [50])[0], default=50, minimum=1, maximum=500)
        logs = self.read_service_logs(unit, lines)
        self.send_json({
            'unit': unit,
            'logs': logs
        })

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

    def handle_nat64_connections(self):
        """Get NAT64 translations from conntrack"""
        if not NAT64_PREFIX:
            self.send_json({'enabled': False, 'connections': []})
            return

        try:
            self.send_json({
                'enabled': True,
                'prefix': NAT64_PREFIX,
                'pool': NAT64_POOL,
                'connections': self.get_nat64_connections()
            })
        except Exception as e:
            self.send_error_json(500, str(e))

    def get_nat64_connections(self, limit=100):
        """Extract NAT64 translations from conntrack table"""
        connections = []
        try:
            # conntrack -L lists all entries
            result = subprocess.run(
                ['conntrack', '-L', '-o', 'extended'],
                capture_output=True, text=True, timeout=5,
                env={**os.environ, 'LC_ALL': 'C'}
            )
            
            # NAT64 prefix without CIDR for matching
            prefix_base = NAT64_PREFIX.split('/')[0]
            pool_base = NAT64_POOL.split('/')[0].rsplit('.', 1)[0] # e.g., 192.168.255

            for line in result.stdout.split('\n'):
                if not line.strip():
                    continue
                
                # We look for connections where one side is the NAT64 prefix
                # and the other is the NAT64 pool.
                if prefix_base in line and pool_base in line:
                    parts = line.split()
                    conn = {}
                    
                    # Simple parser for conntrack output
                    # Format: ipv4 2 tcp 6 431981 ESTABLISHED src=192.168.255.1 dst=8.8.8.8 sport=...
                    # or for IPv6 side: src=2001:db8::... dst=64:ff9b::8.8.8.8
                    
                    try:
                        conn['proto'] = parts[2]
                        for part in parts:
                            if part.startswith('src='):
                                if 'src' not in conn: conn['src'] = part.split('=')[1]
                                else: conn['reply_src'] = part.split('=')[1]
                            elif part.startswith('dst='):
                                if 'dst' not in conn: conn['dst'] = part.split('=')[1]
                                else: conn['reply_dst'] = part.split('=')[1]
                            elif part.startswith('sport='):
                                if 'sport' not in conn: conn['sport'] = part.split('=')[1]
                                else: conn['reply_sport'] = part.split('=')[1]
                            elif part.startswith('dport='):
                                if 'dport' not in conn: conn['dport'] = part.split('=')[1]
                                else: conn['reply_dport'] = part.split('=')[1]
                        
                        if 'src' in conn:
                            connections.append(conn)
                    except (IndexError, ValueError):
                        continue

                if len(connections) >= limit:
                    break
        except Exception:
            pass
        return connections

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

            if not self.technitium_response_ok(stats_data):
                self.send_json({
                    'available': False,
                    'message': self.technitium_error_message(stats_data, 'Failed to get DNS stats')
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
                main_chart.get('totalBlocked'),
                stats.get('totalBlockedQueries'),
                stats.get('totalBlocked'),
                response.get('totalBlockedQueries'),
                response.get('totalBlocked')
            )
            total_cached = self.sum_numeric_values(
                main_chart.get('totalCachedQueries'),
                main_chart.get('totalCached'),
                stats.get('totalCachedQueries'),
                stats.get('totalCached'),
                response.get('totalCachedQueries'),
                response.get('totalCached')
            )
            cached_entries = self.sum_numeric_values(
                stats.get('cachedEntries'),
                response.get('cachedEntries')
            )

            # Get top stats
            top_url = f"{TECHNITIUM_URL}/api/dashboard/stats/getTop?token={token}&type=LastHour&statsType=TopDomains&limit=5&utc=true"
            top_data = self.fetch_technitium_api(top_url)
            top_domains = []
            if self.technitium_response_ok(top_data):
                top_response = top_data.get('response', {})
                top_domains = (top_response.get('topDomains')
                               or top_response.get('domains')
                               or top_response.get('items')
                               or [])[:5]

            # Get top clients
            clients_url = f"{TECHNITIUM_URL}/api/dashboard/stats/getTop?token={token}&type=LastHour&statsType=TopClients&limit=5&utc=true"
            clients_data = self.fetch_technitium_api(clients_url)
            top_clients = []
            if self.technitium_response_ok(clients_data):
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
                'cachedEntries': cached_entries,
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

            if not self.technitium_response_ok(scopes_data):
                self.send_json({
                    'available': False,
                    'message': self.technitium_error_message(scopes_data, 'Failed to get DHCP scopes')
                })
                return

            scopes = scopes_data.get('response', {}).get('scopes', [])
            all_leases = []
            scope_stats = []
            sections = []

            # Get all leases (single API call for all scopes)
            leases_url = f"{TECHNITIUM_URL}/api/dhcp/leases/list?token={token}"
            leases_data = self.fetch_technitium_api(leases_url)
            all_raw_leases = []
            if self.technitium_response_ok(leases_data):
                all_raw_leases = leases_data.get('response', {}).get('leases', [])

            for scope in scopes:
                scope_name = scope.get('name', 'unknown')
                interface_name = (
                    scope.get('interface')
                    or scope.get('interfaceName')
                    or scope.get('networkInterface')
                    or scope.get('adapter')
                    or scope_name
                )

                # Filter leases for this scope
                leases = [l for l in all_raw_leases if l.get('scope') == scope_name]

                # Add scope info
                scope_stats.append({
                    'name': scope_name,
                    'interface': interface_name,
                    'enabled': scope.get('enabled', False),
                    'startAddress': scope.get('startingAddress', ''),
                    'endAddress': scope.get('endingAddress', ''),
                    'leaseCount': len(leases)
                })

                section_leases = []
                # Add leases with scope name (show all from this scope)
                for lease in leases:
                    lease_entry = {
                        'scope': scope_name,
                        'interface': interface_name,
                        'address': lease.get('address', ''),
                        'hostname': lease.get('hostName', ''),
                        'hardwareAddress': lease.get('hardwareAddress', ''),
                        'leaseExpires': lease.get('leaseExpires', ''),
                        'type': lease.get('type', '')
                    }
                    all_leases.append(lease_entry)
                    section_leases.append(lease_entry)

                sections.append({
                    'id': scope_name,
                    'title': interface_name if interface_name != scope_name else scope_name,
                    'scope': scope_name,
                    'interface': interface_name,
                    'enabled': scope.get('enabled', False),
                    'startAddress': scope.get('startingAddress', ''),
                    'endAddress': scope.get('endingAddress', ''),
                    'leaseCount': len(section_leases),
                    'leases': section_leases[:50]
                })

            # Calculate real total before truncation
            real_total = len(all_raw_leases)

            self.send_json({
                'available': True,
                'scopes': scope_stats,
                'leases': all_leases[:100],  # Display up to 100 leases
                'sections': sections,
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

    def technitium_response_ok(self, data):
        return bool(data) and data.get('status') == 'ok'

    def technitium_error_message(self, data, default_message):
        if not data:
            return default_message
        status = data.get('status')
        error = data.get('errorMessage')
        if status and status != 'ok':
            return error or f'Technitium API returned {status}'
        return error or default_message

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

    def find_executable(self, candidates, version_args=None):
        """Find first runnable executable from candidate paths"""
        for path in candidates:
            try:
                cmd = [path] + (version_args or [])
                result = subprocess.run(cmd, capture_output=True, timeout=2)
                if result.returncode == 0:
                    return path
            except Exception:
                continue
        return None

    def find_systemctl(self):
        """Find a working systemctl binary"""
        return self.find_executable(
            ['/run/current-system/sw/bin/systemctl', '/usr/bin/systemctl', 'systemctl'],
            ['--version']
        )

    def get_unit_properties(self, systemctl, service, properties):
        """Return selected systemd properties for a unit"""
        candidates = [service]
        if not service.endswith('.service'):
            candidates.append(f'{service}.service')

        property_arg = '--property=' + ','.join(properties)
        for candidate in candidates:
            try:
                result = subprocess.run(
                    [systemctl, 'show', candidate, property_arg],
                    capture_output=True, text=True, timeout=3,
                    env={**os.environ, 'DBUS_SESSION_BUS_ADDRESS': ''}
                )
                if result.returncode != 0:
                    continue

                parsed = {}
                for line in result.stdout.strip().splitlines():
                    if '=' not in line:
                        continue
                    key, value = line.split('=', 1)
                    parsed[key] = value

                if parsed.get('LoadState') == 'not-found':
                    continue

                if parsed:
                    return parsed
            except Exception:
                continue

        return {}

    def get_service_status(self, systemctl, service):
        """Resolve and return status for a systemd unit name"""
        properties = self.get_unit_properties(systemctl, service, ['Id', 'ActiveState', 'LoadState'])
        if properties:
            unit_id = properties.get('Id', service)
            active_state = properties.get('ActiveState', 'unknown')
            return {
                'name': service,
                'unit': unit_id or service,
                'status': active_state or 'unknown',
                'active': active_state == 'active'
            }

        return {
            'name': service,
            'unit': '',
            'status': 'not-found',
            'active': False
        }

    def read_service_logs(self, unit, lines=50):
        """Read recent logs for a systemd unit"""
        result = subprocess.run(
            ['journalctl', '-u', unit, '-n', str(lines), '-o', 'short-iso', '--no-pager'],
            capture_output=True, text=True, timeout=8
        )

        if result.returncode != 0:
            return [result.stderr.strip() or 'journalctl failed']

        return [line for line in result.stdout.splitlines() if line.strip()]

    def read_env_file(self, path):
        """Parse simple KEY=VALUE environment files"""
        values = {}
        try:
            with open(path, 'r') as handle:
                for line in handle:
                    line = line.strip()
                    if not line or line.startswith('#') or '=' not in line:
                        continue
                    key, value = line.split('=', 1)
                    values[key] = value
        except Exception:
            return values
        return values

    def extract_exec_path(self, systemd_exec_value):
        """Extract executable path from systemd show ExecStart output"""
        if not systemd_exec_value:
            return None

        match = re.search(r'path=([^ ;]+)', systemd_exec_value)
        if match:
            return match.group(1)

        try:
            parts = shlex.split(systemd_exec_value)
            return parts[0] if parts else None
        except Exception:
            return None

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

    def parse_os_release(self):
        result = {}
        for line in self.read_file('/etc/os-release').splitlines():
            if '=' not in line:
                continue
            key, value = line.split('=', 1)
            result[key] = value.strip().strip('"')
        return result

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

    def get_boot_time_iso(self):
        try:
            uptime_secs = float(self.read_file('/proc/uptime').split()[0])
            boot_ts = time.time() - uptime_secs
            return time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(boot_ts))
        except:
            return ''

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
            def read_cpu_times():
                with open('/proc/stat', 'r') as f:
                    parts = f.readline().split()

                idle_time = int(parts[4]) + int(parts[5])
                total_time = sum(int(p) for p in parts[1:9])
                return idle_time, total_time

            global CPU_CACHE

            idle_now, total_now = read_cpu_times()
            now = time.time()

            if CPU_CACHE['idle'] is None or CPU_CACHE['total'] is None:
                CPU_CACHE['idle'] = idle_now
                CPU_CACHE['total'] = total_now
                CPU_CACHE['timestamp'] = now
                return CPU_CACHE['usage']

            diff_idle = idle_now - CPU_CACHE['idle']
            diff_total = total_now - CPU_CACHE['total']

            if diff_total > 0:
                current_usage = (1.0 - diff_idle / diff_total) * 100
                elapsed = max(now - CPU_CACHE['timestamp'], 0.0)

                # Exponential smoothing to avoid bursty 1-tick spikes.
                if elapsed <= 0:
                    alpha = 0.25
                else:
                    alpha = min(max(elapsed / 5.0, 0.15), 0.5)

                CPU_CACHE['usage'] = (
                    CPU_CACHE['usage'] * (1.0 - alpha) + current_usage * alpha
                )

            CPU_CACHE['idle'] = idle_now
            CPU_CACHE['total'] = total_now
            CPU_CACHE['timestamp'] = now
            return CPU_CACHE['usage']
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

    def get_cpu_model(self):
        try:
            for line in self.read_file('/proc/cpuinfo').splitlines():
                if line.startswith('model name'):
                    return line.split(':', 1)[1].strip()
        except:
            pass
        return 'unknown'

    def detect_virtualization(self):
        try:
            result = subprocess.run(
                ['systemd-detect-virt'],
                capture_output=True, text=True, timeout=2
            )
            if result.returncode == 0:
                return result.stdout.strip() or 'virtualized'
        except Exception:
            pass
        return 'bare-metal'

    def get_nixos_version(self):
        try:
            result = subprocess.run(
                ['nixos-version'],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass

        os_release = self.parse_os_release()
        return os_release.get('VERSION', 'unknown')

    def get_current_generation(self):
        path = ''
        label = 'unknown'
        try:
            path = os.path.realpath('/run/current-system')
            label = os.path.basename(path)
        except Exception:
            pass
        return {
            'path': path,
            'label': label
        }

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
