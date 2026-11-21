#!/usr/bin/env python3
"""Regression test: the dashboard listen backlog must absorb a polling burst."""

import http.server
import importlib.util
import pathlib
import socket
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("server.py")
SPEC = importlib.util.spec_from_file_location("router_dashboard_server", MODULE_PATH)
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)

# More simultaneous connections than the old default backlog (5) can hold.
BURST = 64


class ListenBacklogTests(unittest.TestCase):
    def test_backlog_is_larger_than_socketserver_default(self):
        self.assertGreaterEqual(server.DashboardHTTPServer.request_queue_size, BURST)

    def test_burst_of_connections_completes_while_not_accepting(self):
        # The server is bound and listening, but serve_forever() never runs, so
        # every connection waits in the accept queue, like a busy accept loop.
        # With backlog 5 the kernel drops SYNs past the queue and connect()
        # times out; with the fix all of them complete the handshake.
        httpd = server.DashboardHTTPServer(
            ("127.0.0.1", 0), http.server.BaseHTTPRequestHandler
        )
        clients = []
        try:
            port = httpd.server_address[1]
            for i in range(BURST):
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                clients.append(sock)
                try:
                    sock.connect(("127.0.0.1", port))
                except OSError as err:
                    self.fail(f"connection {i + 1}/{BURST} failed: {err}")
        finally:
            for sock in clients:
                sock.close()
            httpd.server_close()


if __name__ == "__main__":
    unittest.main()
