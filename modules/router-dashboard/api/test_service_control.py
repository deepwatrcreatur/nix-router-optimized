#!/usr/bin/env python3

import importlib.util
import io
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


class ServiceControlTests(unittest.TestCase):
    def make_handler(self):
        handler = server.RouterAPIHandler.__new__(server.RouterAPIHandler)
        handler.headers = {}
        handler.rfile = io.BytesIO(b"{}")
        handler.send_json = lambda data, status=200: setattr(handler, "_response", (status, data))
        handler.send_error_json = lambda status, message: setattr(handler, "_response", (status, {"error": message}))
        return handler

    def test_require_mutation_auth_rejects_missing_bearer_token(self):
        handler = self.make_handler()

        with tempfile.NamedTemporaryFile("w", delete=False) as token_file:
            token_file.write("super-secret-token\n")
            token_path = token_file.name

        with mock.patch.object(server, "MUTATION_AUTH_TOKEN_FILE", token_path):
            allowed = handler.require_mutation_auth("restart services")

        self.assertFalse(allowed)
        self.assertEqual(handler._response[0], 401)
        self.assertIn("Bearer token required", handler._response[1]["error"])

    def test_require_mutation_auth_accepts_matching_bearer_token(self):
        handler = self.make_handler()
        handler.headers = {"Authorization": "Bearer super-secret-token"}

        with tempfile.NamedTemporaryFile("w", delete=False) as token_file:
            token_file.write("super-secret-token\n")
            token_path = token_file.name

        with mock.patch.object(server, "MUTATION_AUTH_TOKEN_FILE", token_path):
            allowed = handler.require_mutation_auth("restart services")

        self.assertTrue(allowed)

    def test_handle_service_control_rejects_unsupported_action(self):
        handler = self.make_handler()
        payload = {"service": "caddy", "action": "stop"}
        body = json.dumps(payload).encode("utf-8")
        handler.headers = {"Content-Length": str(len(body))}
        handler.rfile = io.BytesIO(body)

        with mock.patch.object(server, "DASHBOARD_SERVICE_CONTROL", [{"name": "caddy", "unit": "caddy.service", "allowedActions": ["restart"]}]):
            handler.handle_service_control()

        self.assertEqual(handler._response[0], 403)
        self.assertIn("Only the restart action is supported", handler._response[1]["error"])

    def test_handle_service_control_restarts_allowlisted_service(self):
        handler = self.make_handler()
        payload = {"service": "caddy", "action": "restart"}
        body = json.dumps(payload).encode("utf-8")
        handler.headers = {"Content-Length": str(len(body))}
        handler.rfile = io.BytesIO(body)
        handler.find_systemctl = lambda: "/run/current-system/sw/bin/systemctl"

        status_calls = [
            {
                "name": "caddy",
                "unit": "caddy.service",
                "systemdUnit": "caddy.service",
                "status": "active",
                "active": True,
            },
            {
                "name": "caddy",
                "unit": "caddy.service",
                "systemdUnit": "caddy.service",
                "status": "active",
                "active": True,
            },
        ]
        handler.get_service_status = lambda _systemctl, _service: status_calls.pop(0)

        with mock.patch.object(
            server,
            "DASHBOARD_SERVICE_CONTROL",
            [{"name": "caddy", "unit": "caddy.service", "allowedActions": ["restart"]}],
        ), mock.patch.object(
            subprocess,
            "run",
            return_value=mock.Mock(returncode=0, stdout="", stderr=""),
        ) as run_mock:
            handler.handle_service_control()

        self.assertEqual(handler._response[0], 200)
        self.assertEqual(handler._response[1]["status"], "ok")
        self.assertEqual(handler._response[1]["service"]["control"]["actions"], ["restart"])
        self.assertEqual(
            run_mock.call_args.args[0],
            ["/run/wrappers/bin/sudo", "/run/current-system/sw/bin/systemctl", "restart", "caddy.service"],
        )


if __name__ == "__main__":
    unittest.main()
