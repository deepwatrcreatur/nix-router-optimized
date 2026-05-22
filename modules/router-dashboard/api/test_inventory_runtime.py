#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import subprocess
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).with_name("server.py")
SPEC = importlib.util.spec_from_file_location("router_dashboard_server", MODULE_PATH)
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


class InventoryRuntimeTests(unittest.TestCase):
    def make_handler(self):
        return server.RouterAPIHandler.__new__(server.RouterAPIHandler)

    def test_decorate_inventory_with_runtime_merges_declared_lease_and_neighbor(self):
        handler = self.make_handler()
        handler.get_runtime_dhcp_leases = lambda: [
            {
                "address": "10.10.200.20",
                "hostname": "printer",
                "hardwareAddress": "11:22:33:44:55:66",
                "leaseExpires": "2026-05-22T12:00:00Z",
                "scope": "LAN",
                "interface": "br-lan",
            }
        ]
        handler.get_runtime_neighbors = lambda: [
            {
                "address": "10.10.200.20",
                "hardwareAddress": "11:22:33:44:55:66",
                "interface": "br-lan",
                "state": "REACHABLE",
            }
        ]

        inventory = {
            "subnets": [
                {
                    "id": "routed:lan",
                    "label": "LAN",
                    "cidr": "10.10.200.0/24",
                    "dynamicPools": [{"start": "10.10.200.100", "end": "10.10.200.199"}],
                    "provenance": [],
                }
            ],
            "hosts": [
                {
                    "id": "kea:10.10.200.20",
                    "label": "printer",
                    "hostname": "printer",
                    "ipv4Address": "10.10.200.20",
                    "macAddress": "11:22:33:44:55:66",
                    "subnetRef": "routed:lan",
                    "sourceKind": "kea-reservation",
                    "provenance": [{"module": "router-kea", "path": "services.router-kea"}],
                }
            ],
            "reservedAddresses": [],
        }

        result = handler.decorate_inventory_with_runtime(inventory)
        host = result["hosts"][0]

        self.assertEqual(host["status"], "leased")
        self.assertIn("reserved", host["reconciliationTags"])
        self.assertIn("leased", host["reconciliationTags"])
        self.assertIn("neighbor", host["reconciliationTags"])
        self.assertEqual(host["runtimeNeighbor"]["state"], "REACHABLE")
        self.assertEqual(len(result["reservedAddresses"]), 1)
        self.assertEqual(result["runtimeSummary"]["liveLeaseCount"], 1)
        self.assertEqual(result["runtimeSummary"]["neighborCount"], 1)
        self.assertEqual(result["subnets"][0]["runtimeSummary"]["declaredHostCount"], 1)

    def test_decorate_inventory_with_runtime_marks_conflict_and_runtime_only_neighbor(self):
        handler = self.make_handler()
        handler.get_runtime_dhcp_leases = lambda: [
            {
                "address": "10.10.200.30",
                "hostname": "camera",
                "hardwareAddress": "aa:bb:cc:dd:ee:ff",
                "leaseExpires": "2026-05-22T12:05:00Z",
                "scope": "LAN",
                "interface": "br-lan",
            }
        ]
        handler.get_runtime_neighbors = lambda: [
            {
                "address": "10.10.200.30",
                "hardwareAddress": "aa:bb:cc:dd:ee:ff",
                "interface": "br-lan",
                "state": "REACHABLE",
            },
            {
                "address": "10.10.200.40",
                "hardwareAddress": "00:11:22:33:44:55",
                "interface": "br-lan",
                "state": "STALE",
            },
        ]

        inventory = {
            "subnets": [
                {
                    "id": "routed:lan",
                    "label": "LAN",
                    "cidr": "10.10.200.0/24",
                    "dynamicPools": [{"start": "10.10.200.100", "end": "10.10.200.199"}],
                    "provenance": [],
                }
            ],
            "hosts": [
                {
                    "id": "kea:10.10.200.30",
                    "label": "camera",
                    "hostname": "camera",
                    "ipv4Address": "10.10.200.30",
                    "macAddress": "11:22:33:44:55:66",
                    "subnetRef": "routed:lan",
                    "sourceKind": "kea-reservation",
                    "provenance": [],
                }
            ],
            "reservedAddresses": [],
        }

        result = handler.decorate_inventory_with_runtime(inventory)
        by_address = {entry["ipv4Address"]: entry for entry in result["hosts"]}

        self.assertEqual(by_address["10.10.200.30"]["status"], "conflict")
        self.assertIn("conflict", by_address["10.10.200.30"]["reconciliationTags"])
        self.assertEqual(by_address["10.10.200.40"]["status"], "stale")
        self.assertIn("runtime-only", by_address["10.10.200.40"]["reconciliationTags"])
        self.assertIn("stale", by_address["10.10.200.40"]["reconciliationTags"])
        self.assertEqual(result["runtimeSummary"]["runtimeOnlyLeaseCount"], 1)
        self.assertEqual(result["runtimeSummary"]["conflictCount"], 1)
        self.assertEqual(result["runtimeSummary"]["staleCount"], 1)

    def test_get_runtime_neighbors_parses_ip_json(self):
        handler = self.make_handler()
        payload = json.dumps([
            {
                "dst": "10.10.200.40",
                "dev": "br-lan",
                "lladdr": "00:11:22:33:44:55",
                "state": ["STALE"],
            },
            {
                "dst": "10.10.200.20",
                "dev": "br-lan",
                "lladdr": "11:22:33:44:55:66",
                "state": ["REACHABLE"],
            },
        ])

        with mock.patch.object(subprocess, "run", return_value=mock.Mock(returncode=0, stdout=payload, stderr="")):
            neighbors = handler.get_runtime_neighbors()

        self.assertEqual([entry["address"] for entry in neighbors], ["10.10.200.20", "10.10.200.40"])
        self.assertEqual(neighbors[1]["state"], "STALE")


if __name__ == "__main__":
    unittest.main()
