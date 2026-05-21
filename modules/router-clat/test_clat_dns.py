#!/usr/bin/env python3
"""Unit tests for the CLAT DNS synthesis and mapping control plane."""

import ipaddress
import json
import os
import struct
import tempfile
import time
import unittest

# Import from the module
import sys
sys.path.insert(0, os.path.dirname(__file__))
from importlib.machinery import SourceFileLoader
clat_dns = SourceFileLoader("clat_dns", os.path.join(os.path.dirname(__file__), "clat-dns.py")).load_module()


def build_query(name, qtype=clat_dns.QTYPE_A, qid=0x1234):
    """Build a minimal DNS query for testing."""
    header = struct.pack("!HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    qname = b""
    for label in name.split("."):
        qname += bytes([len(label)]) + label.encode()
    qname += b"\x00"
    question = qname + struct.pack("!HH", qtype, 1)
    return header + question


def build_response_with_records(query, a_ips=None, aaaa_ips=None, rcode=0, ttl=300):
    """Build a DNS response with given A and AAAA records for testing."""
    qid = struct.unpack("!H", query[:2])[0]
    qdcount = struct.unpack("!H", query[4:6])[0]

    a_ips = a_ips or []
    aaaa_ips = aaaa_ips or []
    ancount = len(a_ips) + len(aaaa_ips)
    flags = 0x8180 | (rcode & 0xF)
    header = struct.pack("!HHHHHH", qid, flags, qdcount, ancount, 0, 0)

    # Echo question section
    offset = 12
    for _ in range(qdcount):
        while offset < len(query):
            length = query[offset]
            if length == 0:
                offset += 1 + 4
                break
            offset += 1 + length
    question = query[12:offset]

    # Build answer section
    name_bytes = clat_dns.extract_query_name_bytes(query)
    answers = b""
    for ip in a_ips:
        rdata = ipaddress.IPv4Address(ip).packed
        answers += name_bytes
        answers += struct.pack("!HHIH", clat_dns.QTYPE_A, 1, ttl, len(rdata))
        answers += rdata
    for ip in aaaa_ips:
        rdata = ipaddress.IPv6Address(ip).packed
        answers += name_bytes
        answers += struct.pack("!HHIH", clat_dns.QTYPE_AAAA, 1, ttl, len(rdata))
        answers += rdata

    return header + question + answers


class TestMappingStore(unittest.TestCase):
    """Tests for the MappingStore class."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.artifact = os.path.join(self.tmpdir, "artifact.json")
        self.store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=60,
            gc_interval=3600,  # long GC to avoid interference
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )

    def test_allocate_new_mapping(self):
        v4 = self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.assertIsNotNone(v4)
        self.assertTrue(ipaddress.IPv4Address(v4) in
                        ipaddress.IPv4Network("100.64.46.0/24"))
        # Should skip .0 (network) and .1 (router addr), start at .2
        self.assertEqual(v4, "100.64.46.2")

    def test_reuse_existing_mapping(self):
        v4a = self.store.lookup_or_allocate("2001:db8::1", "example.com")
        v4b = self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.assertEqual(v4a, v4b)

    def test_different_ipv6_different_ipv4(self):
        v4a = self.store.lookup_or_allocate("2001:db8::1", "a.example.com")
        v4b = self.store.lookup_or_allocate("2001:db8::2", "b.example.com")
        self.assertNotEqual(v4a, v4b)

    def test_mapping_refresh(self):
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        m = self.store.mappings["2001:db8::1"]
        original_expires = m["expiresAt"]
        time.sleep(0.05)
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        m = self.store.mappings["2001:db8::1"]
        self.assertGreater(m["expiresAt"], original_expires)

    def test_gc_removes_expired(self):
        # Create a store with short TTL
        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=0.1,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        store.lookup_or_allocate("2001:db8::1", "example.com")
        self.assertEqual(len(store.mappings), 1)
        time.sleep(0.2)
        removed = store.run_gc()
        self.assertEqual(removed, 1)
        self.assertEqual(len(store.mappings), 0)

    def test_persistence(self):
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.store.lookup_or_allocate("2001:db8::2", "other.com")

        # Create new store from same state dir
        store2 = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=60,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        self.assertEqual(len(store2.mappings), 2)
        self.assertIn("2001:db8::1", store2.mappings)
        self.assertIn("2001:db8::2", store2.mappings)

    def test_artifact_rendered(self):
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.assertTrue(os.path.exists(self.artifact))
        with open(self.artifact) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertEqual(data["mappingCount"], 1)
        self.assertEqual(data["mappings"][0]["ipv6"], "2001:db8::1")

    def test_names_accumulated(self):
        self.store.lookup_or_allocate("2001:db8::1", "a.example.com")
        self.store.lookup_or_allocate("2001:db8::1", "b.example.com")
        m = self.store.mappings["2001:db8::1"]
        self.assertIn("a.example.com", m["names"])
        self.assertIn("b.example.com", m["names"])

    def test_pool_exhaustion(self):
        # /30 has hosts .1 and .2; .1 is reserved for router, leaving only .2
        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/30",
            mapping_ttl=60,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        v1 = store.lookup_or_allocate("2001:db8::1")
        self.assertIsNotNone(v1)
        self.assertEqual(v1, "100.64.46.2")
        v2 = store.lookup_or_allocate("2001:db8::2")
        self.assertIsNone(v2)

    def test_stats(self):
        self.store.lookup_or_allocate("2001:db8::1")
        self.store.lookup_or_allocate("2001:db8::2")
        stats = self.store.get_stats()
        self.assertEqual(stats["active"], 2)
        self.assertEqual(stats["poolUsed"], 2)


class TestDnsHelpers(unittest.TestCase):
    """Tests for DNS wire format helpers."""

    def test_extract_query_name(self):
        query = build_query("example.com")
        name = clat_dns.extract_query_name(query)
        self.assertEqual(name, "example.com")

    def test_extract_query_type(self):
        query_a = build_query("example.com", clat_dns.QTYPE_A)
        self.assertEqual(clat_dns.extract_query_type(query_a), clat_dns.QTYPE_A)
        query_aaaa = build_query("example.com", clat_dns.QTYPE_AAAA)
        self.assertEqual(clat_dns.extract_query_type(query_aaaa), clat_dns.QTYPE_AAAA)

    def test_parse_response_a_records(self):
        query = build_query("example.com")
        resp = build_response_with_records(query, a_ips=["1.2.3.4", "5.6.7.8"])
        a_recs, aaaa_recs, rcode = clat_dns.parse_response_records(resp)
        self.assertEqual(rcode, 0)
        self.assertEqual(len(a_recs), 2)
        self.assertEqual(a_recs[0][0], "1.2.3.4")
        self.assertEqual(len(aaaa_recs), 0)

    def test_parse_response_aaaa_records(self):
        query = build_query("example.com", clat_dns.QTYPE_AAAA)
        resp = build_response_with_records(query, aaaa_ips=["2001:db8::1"])
        a_recs, aaaa_recs, rcode = clat_dns.parse_response_records(resp)
        self.assertEqual(len(aaaa_recs), 1)
        self.assertEqual(aaaa_recs[0][0], "2001:db8::1")

    def test_build_servfail(self):
        query = build_query("example.com")
        resp = clat_dns.build_servfail(query)
        _, flags, _, _, _, _ = struct.unpack("!HHHHHH", resp[:12])
        self.assertEqual(flags & 0xF, 2)  # SERVFAIL


class TestClatResolver(unittest.TestCase):
    """Tests for the ClatResolver synthesis logic."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.artifact = os.path.join(self.tmpdir, "artifact.json")
        self.store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        self.resolver = clat_dns.ClatResolver(
            store=self.store,
            upstreams=[("127.0.0.1", 53)],
        )

    def _mock_forward(self, a_ips=None, aaaa_ips=None, rcode=0, ttl=300):
        """Replace _forward_raw with a mock that returns canned responses."""
        call_count = [0]
        def mock_forward(data):
            call_count[0] += 1
            qtype = clat_dns.extract_query_type(data)
            if qtype == clat_dns.QTYPE_A:
                return build_response_with_records(
                    data, a_ips=a_ips, rcode=rcode, ttl=ttl)
            elif qtype == clat_dns.QTYPE_AAAA:
                return build_response_with_records(
                    data, aaaa_ips=aaaa_ips, rcode=rcode, ttl=ttl)
            return None
        self.resolver._forward_raw = mock_forward
        return call_count

    def test_a_only_passthrough(self):
        """A-only upstream: pass through unchanged."""
        self._mock_forward(a_ips=["93.184.216.34"])
        query = build_query("example.com")
        resp = self.resolver.handle_query(query)
        a_recs, _, _ = clat_dns.parse_response_records(resp)
        self.assertEqual(len(a_recs), 1)
        self.assertEqual(a_recs[0][0], "93.184.216.34")
        # No mapping should have been created
        self.assertEqual(len(self.store.mappings), 0)

    def test_aaaa_only_synthesis(self):
        """AAAA-only upstream: synthesize A record."""
        self._mock_forward(aaaa_ips=["2001:db8::1"])
        query = build_query("v6only.example.com")
        resp = self.resolver.handle_query(query)
        a_recs, _, _ = clat_dns.parse_response_records(resp)
        self.assertEqual(len(a_recs), 1)
        # Should be from our pool
        self.assertTrue(
            ipaddress.IPv4Address(a_recs[0][0]) in
            ipaddress.IPv4Network("100.64.46.0/24"))
        # Mapping should exist
        self.assertIn("2001:db8::1", self.store.mappings)

    def test_dual_stack_default_passthrough(self):
        """Dual-stack default: return upstream A unchanged."""
        self._mock_forward(a_ips=["93.184.216.34"], aaaa_ips=["2001:db8::1"])
        query = build_query("dual.example.com")
        resp = self.resolver.handle_query(query)
        a_recs, _, _ = clat_dns.parse_response_records(resp)
        self.assertEqual(a_recs[0][0], "93.184.216.34")
        self.assertEqual(len(self.store.mappings), 0)

    def test_dual_stack_prefer_synthesized(self):
        """Dual-stack with prefer_synthesized: synthesize A."""
        self.resolver.prefer_synthesized = True
        self._mock_forward(a_ips=["93.184.216.34"], aaaa_ips=["2001:db8::1"])
        query = build_query("dual.example.com")
        resp = self.resolver.handle_query(query)
        a_recs, _, _ = clat_dns.parse_response_records(resp)
        # Should be synthesized, not the original
        self.assertNotEqual(a_recs[0][0], "93.184.216.34")
        self.assertIn("2001:db8::1", self.store.mappings)

    def test_nxdomain_passthrough(self):
        """NXDOMAIN: pass through unchanged, no mapping."""
        self._mock_forward(rcode=3)
        query = build_query("nonexistent.example.com")
        resp = self.resolver.handle_query(query)
        _, _, rcode = clat_dns.parse_response_records(resp)
        self.assertEqual(rcode, 3)
        self.assertEqual(len(self.store.mappings), 0)

    def test_upstream_failure_servfail(self):
        """Upstream timeout: return SERVFAIL."""
        self.resolver._forward_raw = lambda data: None
        query = build_query("timeout.example.com")
        resp = self.resolver.handle_query(query)
        _, flags, _, _, _, _ = struct.unpack("!HHHHHH", resp[:12])
        self.assertEqual(flags & 0xF, 2)  # SERVFAIL

    def test_deterministic_destination_selection(self):
        """Multiple AAAA records: pick deterministically (sorted first)."""
        self._mock_forward(aaaa_ips=["2001:db8::ff", "2001:db8::01", "2001:db8::aa"])
        query = build_query("multi.example.com")
        self.resolver.handle_query(query)
        # Should have picked the sorted-first IPv6
        self.assertIn("2001:db8::1", self.store.mappings)
        self.assertEqual(len(self.store.mappings), 1)

    def test_reuse_existing_mapping_from_multi_aaaa(self):
        """If an existing mapping matches one of the AAAA records, reuse it."""
        # Pre-allocate a mapping for the "middle" address
        self.store.lookup_or_allocate("2001:db8::aa", "pre.example.com")
        self._mock_forward(aaaa_ips=["2001:db8::ff", "2001:db8::01", "2001:db8::aa"])
        query = build_query("multi.example.com")
        self.resolver.handle_query(query)
        # Should reuse the existing mapping for ::aa, not create a new one for ::01
        a_recs, _, _ = clat_dns.parse_response_records(
            self.resolver.handle_query(query))
        mapped_v4 = self.store.mappings["2001:db8::aa"]["ipv4"]
        self.assertEqual(a_recs[0][0], mapped_v4)

    def test_ttl_clamping(self):
        """Synthesized TTL should be clamped to min(upstream, remaining mapping life)."""
        self._mock_forward(aaaa_ips=["2001:db8::1"], ttl=7200)
        query = build_query("example.com")
        resp = self.resolver.handle_query(query)
        a_recs, _, _ = clat_dns.parse_response_records(resp)
        # TTL should be <= mapping_ttl (1800), not the upstream 7200
        self.assertLessEqual(a_recs[0][1], 1800)

    def test_non_a_query_forwarded(self):
        """Non-A queries (e.g. AAAA, MX) should be forwarded as-is."""
        calls = self._mock_forward(aaaa_ips=["2001:db8::1"])
        query = build_query("example.com", clat_dns.QTYPE_AAAA)
        resp = self.resolver.handle_query(query)
        self.assertIsNotNone(resp)
        # No mapping created for non-A queries
        self.assertEqual(len(self.store.mappings), 0)


class TestClatStatusServer(unittest.TestCase):
    """Tests for the ClatStatusServer status generation."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.artifact = os.path.join(self.tmpdir, "artifact.json")
        self.status_path = os.path.join(self.tmpdir, "status.json")
        self.store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        # Create a mock DNS server object
        class MockServer:
            running = True
            port = 53
        self.mock_server = MockServer()

        self.status_server = clat_dns.ClatStatusServer(
            store=self.store,
            server=self.mock_server,
            status_path=self.status_path,
            port=0,  # won't actually bind
        )

    def test_status_active_idle(self):
        """Active with no mappings should be active-idle."""
        # Mock tayga check to return True
        self.status_server._check_tayga_health = lambda: True
        status = self.status_server.get_status()
        self.assertEqual(status["state"], "active-idle")
        self.assertTrue(status["backend"]["healthy"])
        self.assertTrue(status["dns"]["listening"])
        self.assertEqual(status["mappings"]["active"], 0)

    def test_status_active_translating(self):
        """Active with mappings should be active-translating."""
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.status_server._check_tayga_health = lambda: True
        status = self.status_server.get_status()
        self.assertEqual(status["state"], "active-translating")
        self.assertEqual(status["mappings"]["active"], 1)

    def test_status_degraded(self):
        """Backend unhealthy should be degraded."""
        self.status_server._check_tayga_health = lambda: False
        status = self.status_server.get_status()
        self.assertEqual(status["state"], "degraded")
        self.assertFalse(status["backend"]["healthy"])

    def test_status_inactive(self):
        """Server not running should be inactive."""
        self.mock_server.running = False
        self.status_server._check_tayga_health = lambda: True
        status = self.status_server.get_status()
        self.assertEqual(status["state"], "inactive")

    def test_status_boundaries(self):
        """Status should expose non-HA boundary."""
        self.status_server._check_tayga_health = lambda: True
        status = self.status_server.get_status()
        self.assertFalse(status["boundaries"]["ha"])
        self.assertFalse(status["boundaries"]["multiWan"])
        self.assertIn("Single-owner", status["boundaries"]["note"])

    def test_write_status_file(self):
        """Status file should be written to disk."""
        self.status_server._check_tayga_health = lambda: True
        self.status_server.write_status_file()
        self.assertTrue(os.path.exists(self.status_path))
        with open(self.status_path) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertIn("state", data)

    def test_status_version_field(self):
        """Status should have version 1."""
        self.status_server._check_tayga_health = lambda: True
        status = self.status_server.get_status()
        self.assertEqual(status["version"], 1)


class TestArtifactRendering(unittest.TestCase):
    """Tests for deterministic artifact rendering."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.artifact = os.path.join(self.tmpdir, "artifact.json")
        self.store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )

    def test_artifact_schema(self):
        """Artifact must match the documented backend-neutral schema."""
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        self.store.lookup_or_allocate("2001:db8::2", "other.com")
        with open(self.artifact) as f:
            data = json.load(f)
        self.assertEqual(data["version"], 1)
        self.assertIn("generatedAt", data)
        self.assertEqual(data["mappingCount"], 2)
        for m in data["mappings"]:
            self.assertIn("ipv4", m)
            self.assertIn("ipv6", m)
            self.assertIn("expiresAt", m)
            self.assertEqual(m["state"], "active")

    def test_artifact_deterministic(self):
        """Same mappings should produce identical artifacts (minus timestamp)."""
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        with open(self.artifact) as f:
            a1 = json.load(f)
        # Re-render by touching the mapping
        self.store.lookup_or_allocate("2001:db8::1", "example.com")
        with open(self.artifact) as f:
            a2 = json.load(f)
        # Mappings content should match
        self.assertEqual(a1["mappings"][0]["ipv4"], a2["mappings"][0]["ipv4"])
        self.assertEqual(a1["mappings"][0]["ipv6"], a2["mappings"][0]["ipv6"])
        self.assertEqual(a1["mappingCount"], a2["mappingCount"])

    def test_artifact_gc_removes_expired(self):
        """Artifact should reflect GC by removing expired entries."""
        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=0.1,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        store.lookup_or_allocate("2001:db8::1", "example.com")
        with open(self.artifact) as f:
            before = json.load(f)
        self.assertEqual(before["mappingCount"], 1)

        time.sleep(0.2)
        store.run_gc()
        with open(self.artifact) as f:
            after = json.load(f)
        self.assertEqual(after["mappingCount"], 0)


if __name__ == "__main__":
    unittest.main()
