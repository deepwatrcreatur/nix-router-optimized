#!/usr/bin/env python3
"""router-clat DNS synthesis and mapping control plane.

A forwarding resolver with synthesis capability for an explicitly bounded
client set. Forwards upstream, synthesizes A records from AAAA-only answers
using a local IPv4 mapping pool, and manages mapping state with persistence
and garbage collection.

Design contract: docs/DECLARATIVE_CLAT.md
"""

import argparse
import json
import ipaddress
import logging
import os
import signal
import socket
import struct
import sys
import threading
import time

logger = logging.getLogger("clat-dns")

# ---------------------------------------------------------------------------
# Mapping state
# ---------------------------------------------------------------------------

class MappingStore:
    """Thread-safe IPv6->IPv4 mapping store with persistence and GC."""

    def __init__(self, pool_cidr, mapping_ttl, gc_interval, state_dir,
                 artifact_path, on_artifact_rendered=None):
        net = ipaddress.IPv4Network(pool_cidr, strict=False)
        # First address is reserved for the Tayga router address
        all_hosts = list(net.hosts())
        self.pool_start = all_hosts[1] if len(all_hosts) > 1 else all_hosts[0]
        self.pool_end = all_hosts[-1]
        self.pool_net = net
        self.mapping_ttl = mapping_ttl
        self.gc_interval = gc_interval
        self.state_dir = state_dir
        self.state_file = os.path.join(state_dir, "mappings.json")
        self.artifact_path = artifact_path
        self.on_artifact_rendered = on_artifact_rendered

        self.lock = threading.Lock()
        # ipv6_str -> mapping dict
        self.mappings = {}
        # set of allocated IPv4 addresses (as strings)
        self.allocated_v4 = set()

        self._load_state()
        self._gc_timer = None
        self._start_gc()

    def _load_state(self):
        """Load persisted mapping state from disk."""
        if not os.path.exists(self.state_file):
            return
        try:
            with open(self.state_file) as f:
                data = json.load(f)
            now = time.time()
            for m in data.get("mappings", []):
                expires = m.get("expiresAt", 0)
                if expires > now and m.get("state") == "active":
                    self.mappings[m["ipv6"]] = m
                    self.allocated_v4.add(m["ipv4"])
            logger.info("Loaded %d active mappings from %s",
                        len(self.mappings), self.state_file)
        except (json.JSONDecodeError, KeyError, OSError) as e:
            logger.error("Failed to load mapping state from %s: %s",
                         self.state_file, e)
            raise SystemExit(
                f"State directory corrupt or unreadable: {self.state_file}"
            ) from e

    def _save_state(self):
        """Persist current mapping state to disk. Caller must hold lock."""
        records = list(self.mappings.values())
        data = {
            "version": 1,
            "savedAt": time.time(),
            "mappings": records,
        }
        tmp = self.state_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, self.state_file)

    def _render_artifact(self):
        """Render the backend-neutral mapping artifact. Caller must hold lock."""
        active = [m for m in self.mappings.values() if m["state"] == "active"]
        artifact = {
            "version": 1,
            "generatedAt": time.time(),
            "mappingCount": len(active),
            "mappings": [
                {
                    "ipv4": m["ipv4"],
                    "ipv6": m["ipv6"],
                    "expiresAt": m["expiresAt"],
                    "state": m["state"],
                }
                for m in active
            ],
        }
        tmp = self.artifact_path + ".tmp"
        os.makedirs(os.path.dirname(self.artifact_path), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(artifact, f, indent=2)
        os.replace(tmp, self.artifact_path)

        if self.on_artifact_rendered:
            self.on_artifact_rendered()

    def _next_free_v4(self):
        """Find the next available IPv4 from the pool. Caller must hold lock."""
        candidate = self.pool_start
        while candidate <= self.pool_end:
            s = str(candidate)
            if s not in self.allocated_v4:
                return s
            candidate = ipaddress.IPv4Address(int(candidate) + 1)
        return None

    def lookup_or_allocate(self, ipv6_addr, dns_name=None):
        """Get or create a mapping for a destination IPv6 address.

        Returns the mapped IPv4 string, or None if pool exhausted.
        """
        now = time.time()
        with self.lock:
            existing = self.mappings.get(ipv6_addr)
            if existing and existing["expiresAt"] > now:
                # Refresh
                existing["lastDnsAnswerAt"] = now
                existing["expiresAt"] = now + self.mapping_ttl
                if dns_name and dns_name not in existing["names"]:
                    existing["names"].append(dns_name)
                self._save_state()
                self._render_artifact()
                return existing["ipv4"]

            # Allocate new
            v4 = self._next_free_v4()
            if v4 is None:
                logger.warning("IPv4 pool exhausted, cannot allocate for %s",
                               ipv6_addr)
                return None

            mapping = {
                "version": 1,
                "ipv4": v4,
                "ipv6": ipv6_addr,
                "names": [dns_name] if dns_name else [],
                "createdAt": now,
                "lastDnsAnswerAt": now,
                "lastFlowSeenAt": None,
                "expiresAt": now + self.mapping_ttl,
                "state": "active",
            }
            self.mappings[ipv6_addr] = mapping
            self.allocated_v4.add(v4)
            logger.info("Allocated mapping: %s -> %s (name=%s)",
                        ipv6_addr, v4, dns_name)
            self._save_state()
            self._render_artifact()
            return v4

    def run_gc(self):
        """Remove expired mappings."""
        now = time.time()
        removed = 0
        with self.lock:
            expired_keys = [
                k for k, m in self.mappings.items()
                if m["expiresAt"] <= now
            ]
            for k in expired_keys:
                m = self.mappings.pop(k)
                self.allocated_v4.discard(m["ipv4"])
                removed += 1
            if removed:
                logger.info("GC removed %d expired mappings", removed)
                self._save_state()
                self._render_artifact()
        return removed

    def _start_gc(self):
        """Schedule periodic GC."""
        def gc_loop():
            while True:
                time.sleep(self.gc_interval)
                self.run_gc()
        t = threading.Thread(target=gc_loop, daemon=True)
        t.start()

    def get_stats(self):
        """Return mapping statistics."""
        with self.lock:
            now = time.time()
            active = sum(1 for m in self.mappings.values()
                         if m["expiresAt"] > now)
            return {
                "total": len(self.mappings),
                "active": active,
                "poolUsed": len(self.allocated_v4),
                "poolSize": int(self.pool_end) - int(self.pool_start) + 1,
            }


# ---------------------------------------------------------------------------
# Minimal DNS wire format helpers (no external dependency for the DNS layer)
# ---------------------------------------------------------------------------
# We use dnspython for the heavy lifting but keep the forwarding simple.

def parse_dns_header(data):
    """Parse DNS header, return (id, flags, qdcount, ancount, nscount, arcount)."""
    if len(data) < 12:
        return None
    return struct.unpack("!HHHHHH", data[:12])


def build_dns_response(query_data, answers, rcode=0):
    """Build a minimal DNS response from query + answer records.

    answers: list of (name_bytes, rtype, rclass, ttl, rdata_bytes)
    """
    if len(query_data) < 12:
        return None
    qid = struct.unpack("!H", query_data[:2])[0]
    # QR=1, AA=0, TC=0, RD=1, RA=1, rcode
    flags = 0x8180 | (rcode & 0xF)
    # Parse question section to echo it back
    qdcount = struct.unpack("!H", query_data[4:6])[0]
    # Find end of question section
    offset = 12
    for _ in range(qdcount):
        while offset < len(query_data):
            length = query_data[offset]
            if length == 0:
                offset += 1 + 4  # null byte + qtype + qclass
                break
            offset += 1 + length
        else:
            return None

    question_section = query_data[12:offset]
    header = struct.pack("!HHHHHH", qid, flags, qdcount, len(answers), 0, 0)
    response = header + question_section
    for name_bytes, rtype, rclass, ttl, rdata in answers:
        response += name_bytes
        response += struct.pack("!HHIH", rtype, rclass, ttl, len(rdata))
        response += rdata
    return response


def build_servfail(query_data):
    """Build a SERVFAIL response."""
    if len(query_data) < 12:
        return query_data
    qid = struct.unpack("!H", query_data[:2])[0]
    flags = 0x8182  # QR=1, RD=1, RA=1, RCODE=2 (SERVFAIL)
    qdcount = struct.unpack("!H", query_data[4:6])[0]
    offset = 12
    for _ in range(qdcount):
        while offset < len(query_data):
            length = query_data[offset]
            if length == 0:
                offset += 1 + 4
                break
            offset += 1 + length
    question_section = query_data[12:offset]
    return struct.pack("!HHHHHH", qid, flags, qdcount, 0, 0, 0) + question_section


def extract_query_name(data):
    """Extract the query name from a DNS query as a string."""
    offset = 12
    labels = []
    while offset < len(data):
        length = data[offset]
        if length == 0:
            break
        offset += 1
        labels.append(data[offset:offset + length].decode("ascii", errors="replace"))
        offset += length
    return ".".join(labels) if labels else ""


def extract_query_name_bytes(data):
    """Extract the raw query name bytes (including length octets and null terminator)."""
    offset = 12
    start = offset
    while offset < len(data):
        length = data[offset]
        if length == 0:
            offset += 1
            break
        offset += 1 + length
    return data[start:offset]


def extract_query_type(data):
    """Extract QTYPE from a DNS query."""
    offset = 12
    while offset < len(data):
        length = data[offset]
        if length == 0:
            offset += 1
            break
        offset += 1 + length
    if offset + 2 <= len(data):
        return struct.unpack("!H", data[offset:offset + 2])[0]
    return None


# DNS record types
QTYPE_A = 1
QTYPE_AAAA = 28


def forward_query(data, upstream, timeout=5):
    """Forward a DNS query to upstream and return the response."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(data, upstream)
        resp, _ = sock.recvfrom(4096)
        return resp
    except socket.timeout:
        logger.warning("Upstream DNS timeout for %s:%d", *upstream)
        return None
    finally:
        sock.close()


def parse_response_records(data):
    """Parse A and AAAA records from a DNS response.

    Returns (a_records, aaaa_records, rcode) where each record is
    (ip_string, ttl).
    """
    if len(data) < 12:
        return [], [], 0
    _, flags, qdcount, ancount, _, _ = struct.unpack("!HHHHHH", data[:12])
    rcode = flags & 0xF

    # Skip question section
    offset = 12
    for _ in range(qdcount):
        while offset < len(data):
            length = data[offset]
            if length == 0:
                offset += 1 + 4
                break
            if length >= 192:  # compression pointer
                offset += 2 + 4
                break
            offset += 1 + length

    a_records = []
    aaaa_records = []
    for _ in range(ancount):
        if offset >= len(data):
            break
        # Skip name (handle compression)
        while offset < len(data):
            length = data[offset]
            if length == 0:
                offset += 1
                break
            if length >= 192:
                offset += 2
                break
            offset += 1 + length

        if offset + 10 > len(data):
            break
        rtype, rclass, ttl, rdlength = struct.unpack("!HHIH", data[offset:offset + 10])
        offset += 10
        if offset + rdlength > len(data):
            break
        rdata = data[offset:offset + rdlength]
        offset += rdlength

        if rtype == QTYPE_A and rdlength == 4:
            ip = str(ipaddress.IPv4Address(rdata))
            a_records.append((ip, ttl))
        elif rtype == QTYPE_AAAA and rdlength == 16:
            ip = str(ipaddress.IPv6Address(rdata))
            aaaa_records.append((ip, ttl))

    return a_records, aaaa_records, rcode


# ---------------------------------------------------------------------------
# DNS synthesis logic
# ---------------------------------------------------------------------------

class ClatResolver:
    """Forwarding resolver with CLAT synthesis."""

    def __init__(self, store, upstreams, prefer_synthesized=False):
        self.store = store
        self.upstreams = upstreams  # list of (host, port)
        self.prefer_synthesized = prefer_synthesized

    def handle_query(self, query_data):
        """Process a DNS query and return the response bytes."""
        qtype = extract_query_type(query_data)
        qname = extract_query_name(query_data)

        # Only synthesize for A queries
        if qtype != QTYPE_A:
            return self._forward_raw(query_data)

        # Forward as-is to get the A answer
        a_response = self._forward_raw(query_data)
        if a_response is None:
            return build_servfail(query_data)

        a_records, _, a_rcode = parse_response_records(a_response)

        # Also query for AAAA to decide synthesis behavior
        aaaa_query = self._rewrite_qtype(query_data, QTYPE_AAAA)
        aaaa_response = self._forward_raw(aaaa_query)
        aaaa_records = []
        if aaaa_response:
            _, aaaa_records, _ = parse_response_records(aaaa_response)

        # NXDOMAIN/NODATA: pass through
        if a_rcode in (3, 0) and not a_records and not aaaa_records:
            return a_response

        # A-only upstream: pass through unchanged
        if a_records and not aaaa_records:
            return a_response

        # Dual-stack: by default return A unchanged
        if a_records and aaaa_records and not self.prefer_synthesized:
            return a_response

        # AAAA-only (or dual-stack with prefer_synthesized): synthesize
        if aaaa_records:
            return self._synthesize_a(query_data, qname, aaaa_records)

        # Fallback: pass through original A response
        return a_response

    def _synthesize_a(self, query_data, qname, aaaa_records):
        """Synthesize an A response from AAAA records."""
        # Deterministic destination selection: sort and pick first,
        # or reuse existing mapping
        sorted_v6 = sorted(aaaa_records, key=lambda r: r[0])

        # Check for existing mapping
        target = None
        target_ttl = sorted_v6[0][1]
        for ip6, ttl in sorted_v6:
            if ip6 in self.store.mappings:
                m = self.store.mappings[ip6]
                if m["expiresAt"] > time.time():
                    target = ip6
                    target_ttl = ttl
                    break
        if target is None:
            target = sorted_v6[0][0]
            target_ttl = sorted_v6[0][1]

        v4 = self.store.lookup_or_allocate(target, dns_name=qname)
        if v4 is None:
            logger.error("Pool exhausted, returning SERVFAIL for %s", qname)
            return build_servfail(query_data)

        # Clamp TTL: min(upstream AAAA TTL, remaining mapping lifetime)
        remaining = self.store.mappings.get(target, {}).get("expiresAt", 0) - time.time()
        synth_ttl = max(1, int(min(target_ttl, remaining)))

        name_bytes = extract_query_name_bytes(query_data)
        rdata = ipaddress.IPv4Address(v4).packed
        answers = [(name_bytes, QTYPE_A, 1, synth_ttl, rdata)]

        logger.debug("Synthesized A %s -> %s for %s (TTL %d)",
                      qname, v4, target, synth_ttl)
        return build_dns_response(query_data, answers)

    def _forward_raw(self, data):
        """Try each upstream until one responds."""
        for upstream in self.upstreams:
            resp = forward_query(data, upstream)
            if resp is not None:
                return resp
        return None

    def _rewrite_qtype(self, data, new_qtype):
        """Rewrite the QTYPE in a DNS query."""
        # Find end of QNAME
        offset = 12
        while offset < len(data):
            length = data[offset]
            if length == 0:
                offset += 1
                break
            offset += 1 + length
        # Replace QTYPE (2 bytes at offset)
        return data[:offset] + struct.pack("!H", new_qtype) + data[offset + 2:]


# ---------------------------------------------------------------------------
# UDP server
# ---------------------------------------------------------------------------

class ClatDnsServer:
    """UDP DNS server bound to specific interfaces."""

    def __init__(self, resolver, bind_addresses, port):
        self.resolver = resolver
        self.bind_addresses = bind_addresses
        self.port = port
        self.sockets = []
        self.running = False

    def start(self):
        self.running = True
        for addr in self.bind_addresses:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((addr, self.port))
            sock.settimeout(1.0)
            self.sockets.append(sock)
            logger.info("Listening on %s:%d", addr, self.port)

        threads = []
        for sock in self.sockets:
            t = threading.Thread(target=self._serve, args=(sock,), daemon=True)
            t.start()
            threads.append(t)

        # Wait for shutdown
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            self.stop()

    def stop(self):
        self.running = False
        for sock in self.sockets:
            sock.close()

    def _serve(self, sock):
        while self.running:
            try:
                data, addr = sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break

            try:
                response = self.resolver.handle_query(data)
                if response:
                    sock.sendto(response, addr)
            except Exception:
                logger.exception("Error handling query from %s", addr)
                try:
                    sock.sendto(build_servfail(data), addr)
                except OSError:
                    pass


# ---------------------------------------------------------------------------
# Status / observability
# ---------------------------------------------------------------------------

class ClatStatusServer:
    """Lightweight HTTP server exposing runtime health and mapping status.

    Writes a JSON status file on each update so the dashboard can read it
    without depending on this process being responsive.
    """

    def __init__(self, store, server, status_path, port=9467):
        self.store = store
        self.dns_server = server
        self.status_path = status_path
        self.port = port
        self.start_time = time.time()
        self._last_status_write = 0

    def start(self):
        """Start the HTTP status server in a background thread."""
        from http.server import HTTPServer, BaseHTTPRequestHandler

        parent = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self_handler):
                if self_handler.path == "/status":
                    status = parent.get_status()
                    body = json.dumps(status, indent=2).encode()
                    self_handler.send_response(200)
                    self_handler.send_header("Content-Type", "application/json")
                    self_handler.send_header("Content-Length", str(len(body)))
                    self_handler.end_headers()
                    self_handler.wfile.write(body)
                else:
                    self_handler.send_error(404)

            def log_message(self_handler, format, *args):
                pass  # suppress access logs

        def serve():
            httpd = HTTPServer(("127.0.0.1", self.port), Handler)
            httpd.serve_forever()

        t = threading.Thread(target=serve, daemon=True)
        t.start()
        logger.info("Status endpoint listening on 127.0.0.1:%d/status", self.port)

        # Start periodic status file writer
        def write_loop():
            while True:
                self.write_status_file()
                time.sleep(10)
        wt = threading.Thread(target=write_loop, daemon=True)
        wt.start()

    def get_status(self):
        """Build the runtime status object."""
        stats = self.store.get_stats()
        now = time.time()
        uptime = now - self.start_time

        # Check backend health by looking for the Tayga service
        tayga_healthy = self._check_tayga_health()

        # Determine overall state
        if not self.dns_server.running:
            state = "inactive"
        elif not tayga_healthy:
            state = "degraded"
        elif stats["active"] == 0:
            state = "active-idle"
        else:
            state = "active-translating"

        return {
            "version": 1,
            "timestamp": now,
            "state": state,
            "uptime": round(uptime, 1),
            "backend": {
                "name": "tayga",
                "healthy": tayga_healthy,
            },
            "dns": {
                "listening": self.dns_server.running,
                "listenPort": self.dns_server.port,
            },
            "mappings": stats,
            "boundaries": {
                "ha": False,
                "multiWan": False,
                "note": "Single-owner first-slice. No HA or failover guarantees.",
            },
        }

    def _check_tayga_health(self):
        """Check if the Tayga backend service is running."""
        try:
            result = subprocess.run(
                ["systemctl", "is-active", "router-clat-tayga.service"],
                capture_output=True, text=True, timeout=5,
            )
            return result.stdout.strip() == "active"
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return False

    def write_status_file(self):
        """Write current status to a file for dashboard consumption."""
        try:
            status = self.get_status()
            os.makedirs(os.path.dirname(self.status_path), exist_ok=True)
            tmp = self.status_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(status, f, indent=2)
            os.replace(tmp, self.status_path)
        except OSError as e:
            logger.warning("Failed to write status file: %s", e)


import subprocess  # needed for systemctl check


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="router-clat DNS synthesis and mapping control plane"
    )
    parser.add_argument("--pool", required=True,
                        help="IPv4 CIDR pool for synthetic addresses")
    parser.add_argument("--mapping-ttl", type=int, default=1800,
                        help="Mapping lifetime in seconds (default: 1800)")
    parser.add_argument("--gc-interval", type=int, default=60,
                        help="GC sweep interval in seconds (default: 60)")
    parser.add_argument("--state-dir", required=True,
                        help="Directory for persistent mapping state")
    parser.add_argument("--artifact-path", required=True,
                        help="Path for rendered backend artifact")
    parser.add_argument("--upstream", action="append", required=True,
                        help="Upstream resolver (host:port or host)")
    parser.add_argument("--listen", action="append", required=True,
                        help="Listen address (IP)")
    parser.add_argument("--port", type=int, default=53,
                        help="DNS listen port (default: 53)")
    parser.add_argument("--prefer-synthesized", action="store_true",
                        help="Prefer synthesized A over native A in dual-stack")
    parser.add_argument("--reload-cmd",
                        help="Command to run after artifact render (e.g. reload backend)")
    parser.add_argument("--status-port", type=int, default=9467,
                        help="HTTP port for status endpoint (default: 9467)")
    parser.add_argument("--status-path",
                        help="Path to write JSON status file for dashboard")
    parser.add_argument("--log-level", default="INFO",
                        choices=["DEBUG", "INFO", "WARNING", "ERROR"])

    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    # Parse upstreams
    upstreams = []
    for u in args.upstream:
        if ":" in u:
            host, port = u.rsplit(":", 1)
            upstreams.append((host, int(port)))
        else:
            upstreams.append((u, 53))

    def on_artifact_rendered():
        if args.reload_cmd:
            os.system(args.reload_cmd)

    store = MappingStore(
        pool_cidr=args.pool,
        mapping_ttl=args.mapping_ttl,
        gc_interval=args.gc_interval,
        state_dir=args.state_dir,
        artifact_path=args.artifact_path,
        on_artifact_rendered=on_artifact_rendered,
    )

    resolver = ClatResolver(
        store=store,
        upstreams=upstreams,
        prefer_synthesized=args.prefer_synthesized,
    )

    server = ClatDnsServer(
        resolver=resolver,
        bind_addresses=args.listen,
        port=args.port,
    )

    # Start status/observability endpoint
    status_path = args.status_path or os.path.join(args.state_dir, "status.json")
    status_server = ClatStatusServer(
        store=store,
        server=server,
        status_path=status_path,
        port=args.status_port,
    )
    status_server.start()

    def handle_signal(signum, frame):
        logger.info("Received signal %d, shutting down", signum)
        server.stop()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGHUP, handle_signal)

    logger.info("router-clat control plane starting (pool=%s, ttl=%ds, gc=%ds)",
                args.pool, args.mapping_ttl, args.gc_interval)
    server.start()


if __name__ == "__main__":
    main()
