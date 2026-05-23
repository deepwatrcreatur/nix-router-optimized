#!/usr/bin/env python3

import importlib.util
import pathlib
import unittest


SERVER_PATH = pathlib.Path(__file__).with_name("server.py")
SPEC = importlib.util.spec_from_file_location("router_dashboard_server", SERVER_PATH)
server = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(server)


class FirewallActivitySummaryTests(unittest.TestCase):
    def setUp(self):
        self.handler = server.RouterAPIHandler.__new__(server.RouterAPIHandler)

    def test_parse_firewall_log_line_extracts_key_fields(self):
        line = (
            "2026-05-23T10:15:42-04:00 host kernel: FW-DROP IN=wan0 OUT= "
            "SRC=198.51.100.10 DST=192.0.2.20 PROTO=TCP SPT=4242 DPT=22"
        )

        parsed = self.handler.parse_firewall_log_line(line)

        self.assertEqual(parsed["prefix"], "FW-DROP")
        self.assertEqual(parsed["src"], "198.51.100.10")
        self.assertEqual(parsed["dst"], "192.0.2.20")
        self.assertEqual(parsed["dstPort"], "22")
        self.assertEqual(parsed["protocol"], "TCP")

    def test_summarize_firewall_activity_counts_sources_ports_and_banned_hits(self):
        logs = [
            {
                "timestamp": "2026-05-23T10:15:42-04:00",
                "prefix": "FW-DROP",
                "summary": "Drop: TCP 198.51.100.10:4242 -> 192.0.2.20:22",
                "src": "198.51.100.10",
                "dstPort": "22",
                "protocol": "TCP",
            },
            {
                "timestamp": "2026-05-23T10:16:10-04:00",
                "prefix": "FW-DROP",
                "summary": "Drop: TCP 198.51.100.10:4243 -> 192.0.2.20:22",
                "src": "198.51.100.10",
                "dstPort": "22",
                "protocol": "TCP",
            },
            {
                "timestamp": "2026-05-23T10:17:01-04:00",
                "prefix": "FW-ACCEPT",
                "summary": "Accept: UDP 203.0.113.8:5353 -> 192.0.2.53:53",
                "src": "203.0.113.8",
                "dstPort": "53",
                "protocol": "UDP",
            },
        ]

        summary = self.handler.summarize_firewall_activity(logs, {"198.51.100.10"})

        self.assertEqual(summary["eventsAnalyzed"], 3)
        self.assertEqual(summary["prefixCounts"][0], {"prefix": "FW-DROP", "count": 2})
        self.assertEqual(summary["topSources"][0], {"ip": "198.51.100.10", "count": 2})
        self.assertEqual(summary["topDestinationPorts"][0], {"port": "22", "count": 2})
        self.assertEqual(summary["protocolCounts"][0], {"protocol": "TCP", "count": 2})
        self.assertEqual(summary["bannedSourceHits"][0]["ip"], "198.51.100.10")
        self.assertEqual(summary["mostRecentEvent"]["summary"], logs[-1]["summary"])


if __name__ == "__main__":
    unittest.main()
