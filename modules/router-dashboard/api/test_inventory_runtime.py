#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import subprocess
import tempfile
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
        handler.get_runtime_routes = lambda: [
            {
                "destination": "0.0.0.0/0",
                "interface": "eth0",
                "gatewayAddress": "198.51.100.1",
                "protocol": "dhcp",
                "scope": "global",
                "table": "main",
                "type": "unicast",
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
            "interfaces": [
                {
                    "id": "wan:wan",
                    "name": "wan",
                    "device": "eth0",
                    "role": "wan",
                    "kind": "physical",
                    "provenance": [],
                },
                {
                    "id": "routed:lan",
                    "name": "lan",
                    "device": "eth1",
                    "role": "lan",
                    "kind": "physical",
                    "subnetRefs": ["routed:lan"],
                    "provenance": [],
                },
            ],
            "prefixes": [
                {
                    "id": "prefix:routed:lan",
                    "cidr": "10.10.200.0/24",
                    "label": "LAN",
                    "interfaceRef": "routed:lan",
                    "gatewayAddress": "10.10.200.1",
                    "role": "lan",
                    "dhcpBackend": "kea",
                    "provenance": [],
                }
            ],
            "edges": [
                {
                    "id": "edge:segment:routed:lan",
                    "kind": "segment",
                    "label": "LAN segment",
                    "interfaceRef": "routed:lan",
                    "prefixRef": "prefix:routed:lan",
                    "subnetRef": "routed:lan",
                    "destination": "10.10.200.0/24",
                    "gatewayAddress": "10.10.200.1",
                    "active": True,
                    "confidence": "declared",
                    "inference": "declared",
                    "provenance": [],
                },
                {
                    "id": "edge:upstream:wan:wan",
                    "kind": "upstream",
                    "label": "wan upstream",
                    "interfaceRef": "wan:wan",
                    "prefixRef": None,
                    "subnetRef": None,
                    "destination": "0.0.0.0/0",
                    "gatewayAddress": None,
                    "active": False,
                    "confidence": "declared",
                    "inference": "declared",
                    "provenance": [],
                },
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
        self.assertEqual(result["edgeSummary"]["upstreamCount"], 1)
        upstream = next(edge for edge in result["edges"] if edge["kind"] == "upstream")
        self.assertEqual(upstream["gatewayAddress"], "198.51.100.1")
        self.assertTrue(upstream["active"])
        segment = next(edge for edge in result["edges"] if edge["id"] == "edge:segment:routed:lan")
        self.assertIn(upstream["runtimeRouteRef"], segment["upstreamEdgeRefs"])

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
        payloads = [
            json.dumps([
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
            ]),
            json.dumps([
                {
                    "dst": "2001:db8::20",
                    "dev": "br-lan",
                    "lladdr": "22:33:44:55:66:77",
                    "state": ["REACHABLE"],
                }
            ]),
        ]

        with mock.patch.object(
            subprocess,
            "run",
            side_effect=[mock.Mock(returncode=0, stdout=payload, stderr="") for payload in payloads],
        ):
            neighbors = handler.get_runtime_neighbors()

        self.assertEqual(
            [entry["address"] for entry in neighbors],
            ["10.10.200.20", "10.10.200.40", "2001:db8::20"],
        )
        self.assertEqual(neighbors[1]["state"], "STALE")
        self.assertEqual(neighbors[2]["hardwareAddress"], "22:33:44:55:66:77")

    def test_get_kea_dhcp_leases_prefers_snapshot_file(self):
        handler = self.make_handler()

        with tempfile.TemporaryDirectory() as tempdir:
            lease_file = pathlib.Path(tempdir) / "kea-dhcp4.leases"
            lease_file.write_text(
                "\n".join(
                    [
                        "address,hwaddr,client_id,valid_lifetime,expire,subnet_id,fqdn_fwd,fqdn_rev,hostname,state,user_context,pool_id",
                        "10.10.210.10,11:22:33:44:55:66,,3600,4102444800,1,0,0,printer,0,,0",
                        "10.10.210.11,aa:bb:cc:dd:ee:ff,,3600,1,1,0,0,expired,0,,0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            with mock.patch.object(server, "KEA_LEASE_FILES", [lease_file]):
                leases = handler.get_kea_dhcp_leases()

        self.assertEqual(len(leases), 1)
        self.assertEqual(leases[0]["address"], "10.10.210.10")
        self.assertEqual(leases[0]["hostname"], "printer")
        self.assertEqual(leases[0]["hardwareAddress"], "11:22:33:44:55:66")

    def test_get_runtime_routes_parses_ip_json(self):
        handler = self.make_handler()
        payloads = [
            json.dumps([
                {
                    "dst": "default",
                    "dev": "eth0",
                    "gateway": "198.51.100.1",
                    "protocol": "dhcp",
                    "scope": "global",
                    "table": "main",
                },
                {
                    "dst": "10.10.200.0/24",
                    "dev": "eth1",
                    "protocol": "kernel",
                    "scope": "link",
                    "table": "main",
                },
            ]),
            json.dumps([
                {
                    "dst": "default",
                    "dev": "eth0",
                    "via": "2001:db8::1",
                    "protocol": "ra",
                    "scope": "global",
                    "table": "main",
                },
                {
                    "dst": "2001:db8:200::/64",
                    "dev": "eth1",
                    "protocol": "kernel",
                    "scope": "link",
                    "table": "main",
                },
            ]),
        ]

        with mock.patch.object(
            subprocess,
            "run",
            side_effect=[mock.Mock(returncode=0, stdout=payload, stderr="") for payload in payloads],
        ):
            routes = handler.get_runtime_routes()

        self.assertEqual(routes[0]["destination"], "0.0.0.0/0")
        self.assertEqual(routes[0]["gatewayAddress"], "198.51.100.1")
        self.assertEqual(routes[1]["destination"], "::/0")
        self.assertEqual(routes[1]["gatewayAddress"], "2001:db8::1")
        self.assertEqual(routes[2]["destination"], "10.10.200.0/24")
        self.assertEqual(routes[3]["destination"], "2001:db8:200::/64")


if __name__ == "__main__":
    unittest.main()
