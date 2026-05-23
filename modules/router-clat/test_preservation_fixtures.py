#!/usr/bin/env python3
"""Preservation fixtures for backend-neutral router-clat parity checks."""

import json
import os
import tempfile
import time
import unittest

import sys
sys.path.insert(0, os.path.dirname(__file__))
from importlib.util import module_from_spec, spec_from_file_location

_CLAT_DNS_SPEC = spec_from_file_location(
    "clat_dns",
    os.path.join(os.path.dirname(__file__), "clat-dns.py"),
)
clat_dns = module_from_spec(_CLAT_DNS_SPEC)
_CLAT_DNS_SPEC.loader.exec_module(clat_dns)


FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


def load_fixture(name):
    with open(os.path.join(FIXTURE_DIR, name)) as f:
        return json.load(f)


def assert_generic_status_shape(testcase, status):
    testcase.assertEqual(status["version"], 1)
    testcase.assertIn("state", status)
    testcase.assertIn("backend", status)
    testcase.assertIn("healthy", status["backend"])
    testcase.assertIn("mappings", status)
    testcase.assertIn("boundaries", status)
    testcase.assertIn("ha", status["boundaries"])
    testcase.assertIn("multiWan", status["boundaries"])


def assert_generic_artifact_shape(testcase, artifact, fixture):
    testcase.assertEqual(artifact["version"], fixture["version"])
    testcase.assertIn("generatedAt", artifact)
    testcase.assertEqual(artifact["mappingCount"], fixture["mappingCount"])
    testcase.assertEqual(len(artifact["mappings"]), fixture["mappingCount"])
    for mapping in artifact["mappings"]:
        for key in fixture["requiredMappingKeys"]:
            testcase.assertIn(key, mapping)
        testcase.assertIn(mapping["state"], fixture["requiredStates"])


def build_query(name, qtype=clat_dns.QTYPE_A, qid=0x1234):
    header = clat_dns.struct.pack("!HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    qname = b""
    for label in name.split("."):
        qname += bytes([len(label)]) + label.encode()
    qname += b"\x00"
    question = qname + clat_dns.struct.pack("!HH", qtype, 1)
    return header + question


def build_response_with_records(query, a_ips=None, aaaa_ips=None, rcode=0, ttl=300):
    qid = clat_dns.struct.unpack("!H", query[:2])[0]
    qdcount = clat_dns.struct.unpack("!H", query[4:6])[0]
    a_ips = a_ips or []
    aaaa_ips = aaaa_ips or []
    ancount = len(a_ips) + len(aaaa_ips)
    flags = 0x8180 | (rcode & 0xF)
    header = clat_dns.struct.pack("!HHHHHH", qid, flags, qdcount, ancount, 0, 0)

    offset = 12
    for _ in range(qdcount):
        while offset < len(query):
            length = query[offset]
            if length == 0:
                offset += 1 + 4
                break
            offset += 1 + length
    question = query[12:offset]

    name_bytes = clat_dns.extract_query_name_bytes(query)
    answers = b""
    for ip in a_ips:
        rdata = clat_dns.ipaddress.IPv4Address(ip).packed
        answers += name_bytes
        answers += clat_dns.struct.pack("!HHIH", clat_dns.QTYPE_A, 1, ttl, len(rdata))
        answers += rdata
    for ip in aaaa_ips:
        rdata = clat_dns.ipaddress.IPv6Address(ip).packed
        answers += name_bytes
        answers += clat_dns.struct.pack("!HHIH", clat_dns.QTYPE_AAAA, 1, ttl, len(rdata))
        answers += rdata

    return header + question + answers


class TestPreservationFixtures(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmpdir = self._tmpdir.name
        self.artifact = os.path.join(self.tmpdir, "artifact.json")
        self.status_path = os.path.join(self.tmpdir, "status.json")

    def test_dns_aaaa_only_fixture_matches_python_behavior(self):
        fixture = load_fixture("dns-aaaa-only-synthesis.json")
        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        resolver = clat_dns.ClatResolver(
            store=store,
            upstreams=[("127.0.0.1", 53)],
        )

        def mock_forward(data):
            qtype = clat_dns.extract_query_type(data)
            if qtype == clat_dns.QTYPE_A:
                return build_response_with_records(data, a_ips=fixture["upstream"]["aRecords"])
            return build_response_with_records(data, aaaa_ips=fixture["upstream"]["aaaaRecords"])

        resolver._forward_raw = mock_forward
        query = build_query(fixture["queryName"])
        response = resolver.handle_query(query)
        a_records, _, _ = clat_dns.parse_response_records(response)
        self.assertEqual(len(a_records) > 0, fixture["expected"]["synthesizesARecord"])
        self.assertIn(fixture["expected"]["mappingIpv6"], store.mappings)
        self.assertEqual(len(store.mappings) > 0, fixture["expected"]["allocatesMapping"])

    def test_mapping_gc_fixture_matches_python_behavior(self):
        fixture = load_fixture("mapping-gc-expiry.json")
        store = clat_dns.MappingStore(
            pool_cidr=fixture["poolCidr"],
            mapping_ttl=fixture["mappingTtlSec"],
            gc_interval=fixture["gcIntervalSec"],
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        store.lookup_or_allocate("2001:db8::1", "example.com")
        self.assertEqual(len(store.mappings), fixture["expected"]["beforeGcMappingCount"])
        time.sleep(0.2)
        removed = store.run_gc()
        self.assertEqual(removed, fixture["expected"]["removedMappings"])
        self.assertEqual(len(store.mappings), fixture["expected"]["afterGcMappingCount"])

    def test_artifact_fixture_matches_python_rendering(self):
        fixture = load_fixture("artifact-schema-v1.json")
        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        store.lookup_or_allocate("2001:db8::1", "example.com")
        with open(self.artifact) as f:
            artifact = json.load(f)
        assert_generic_artifact_shape(self, artifact, fixture)

    def test_status_fixture_matches_python_degraded_state(self):
        fixture = load_fixture("status-degraded-backend-unhealthy.json")

        class MockServer:
            running = True
            port = 53

        store = clat_dns.MappingStore(
            pool_cidr="100.64.46.0/24",
            mapping_ttl=1800,
            gc_interval=3600,
            state_dir=self.tmpdir,
            artifact_path=self.artifact,
        )
        status_server = clat_dns.ClatStatusServer(
            store=store,
            server=MockServer(),
            status_path=self.status_path,
            port=0,
        )
        status_server._check_tayga_health = lambda: False
        status = status_server.get_status()
        assert_generic_status_shape(self, status)
        self.assertEqual(status["state"], fixture["state"])
        self.assertEqual(status["backend"]["healthy"], fixture["backend"]["healthy"])
        self.assertEqual(status["boundaries"]["ha"], fixture["boundaries"]["ha"])
        self.assertEqual(status["boundaries"]["multiWan"], fixture["boundaries"]["multiWan"])

    def test_status_schema_accepts_fake_backend_fixture(self):
        fixture = load_fixture("status-fake-backend-generic.json")
        assert_generic_status_shape(self, fixture)
        self.assertEqual(fixture["backend"]["name"], "fake-backend")
        self.assertNotEqual(fixture["backend"]["name"], "tayga")


if __name__ == "__main__":
    unittest.main()
