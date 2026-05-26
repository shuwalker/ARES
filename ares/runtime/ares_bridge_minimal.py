#!/usr/bin/env python3
"""Minimal Hermes bridge — HTTP to Hermes CLI. Drop-in replacement on :9876.

Copied from ~/.hermes/scripts/ares_bridge_minimal.py and runs the cognition bridge.
"""

import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

HOST = "127.0.0.1"
PORT = 9876


def serve() -> None:
    """Run the minimal Hermes bridge HTTP server on HOST:PORT."""
    HTTPServer((HOST, PORT), Handler).serve_forever()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._json({"status": "ok", "backend": "hermes-cli"})
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path == "/think":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            text = body.get("text", "")

            try:
                result = subprocess.run(
                    ["hermes", "-z", text],
                    capture_output=True,
                    text=True,
                    timeout=120,
                    env={**__import__("os").environ, "HERMES_QUIET": "1"},
                )
                response = result.stdout.strip() or result.stderr.strip()
                if not response:
                    response = "I received your message but had no response. Try again."
            except Exception as e:
                response = f"Error: {e}"

            self._json({"response": response, "state": "ok", "expression": "speaking"})
        else:
            self._json({"error": "not found"}, 404)

    def _json(self, data, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, *args):
        pass  # silent


if __name__ == "__main__":
    serve()
