"""ARES cognition bridge.

Local HTTP boundary between the SwiftUI shell and Python cognition services.
The bridge returns a user-facing response plus state/expression hints for the
avatar. Implementation details stay behind this boundary.
"""
from __future__ import annotations

import json
import time
import subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HOST = "127.0.0.1"
PORT = 9876
start_time = time.time()

VALID_STATES = {"idle", "awakened", "listening", "thinking", "speaking", "sleeping", "error"}
VALID_EXPRESSIONS = {
    "neutral", "happy", "curious", "thinking",
    "surprised", "concerned", "excited", "sleepy",
}


def call_mcp(server: int, tool: str, **kwargs) -> dict:
    """Call a local MCP tool via mcporter and normalize failures."""
    args = []
    for k, v in kwargs.items():
        if isinstance(v, str):
            args.append(f"{k}={v}")
        else:
            args.append(f"{k}={json.dumps(v)}")

    cmd = [
        "npx", "-y", "mcporter", "call",
        f"http://localhost:{server}/mcp.{tool}",
        "--allow-http", "--output", "json"
    ] + args

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return {
                "status": "unavailable",
                "error": result.stderr.strip() or f"mcporter exited {result.returncode}",
            }
        if not result.stdout.strip():
            return {"status": "unavailable", "error": "empty MCP response"}
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        return {"status": "unavailable", "error": f"invalid MCP JSON: {e}"}
    except subprocess.TimeoutExpired:
        return {"status": "unavailable", "error": f"{tool} timed out"}
    except Exception as e:
        return {"status": "unavailable", "error": str(e)}


def cognition_query(text: str, session_id: str) -> tuple[str, str, str]:
    """Process a message through the ARES cognition stack.

    Returns: (response_text, agent_state, expression)
    """
    if not text.strip():
        return "I didn't catch that.", "error", "concerned"

    # Fast local responses. The full reasoning engine can replace this behind
    # the same response/state/expression contract.
    text_lower = text.lower().strip()

    if any(g in text_lower for g in ["hello", "hey", "hi ares", "hi aris"]):
        return "Hello Matthew. I'm here.", "awakened", "happy"

    if any(g in text_lower for g in ["how are you", "how's it going", "what's up"]):
        return "Operational. I can listen, respond, and express state through the avatar path.", "speaking", "happy"

    if any(g in text_lower for g in ["look", "see", "what do you see", "describe"]):
        scene = call_mcp(9512, "perception_snapshot")
        if scene.get("status") == "unavailable":
            return "I cannot reach the perception service right now.", "speaking", "concerned"
        summary = scene.get("summary") or scene.get("scene_description") or "no scene summary available"
        return f"I can see: {summary}", "speaking", "curious"

    if any(g in text_lower for g in ["avatar", "face", "expression", "live2d"]):
        return (
            "My expression path is online. If the rendered avatar is unavailable, "
            "the black fire form carries the same emotional state."
        ), "speaking", "excited"

    if any(g in text_lower for g in ["status", "health", "check"]):
        perception = call_mcp(9512, "perception_health")
        voice = call_mcp(9513, "voice_health")
        avatar = call_mcp(9514, "avatar_state")

        perception_ok = perception.get("status") == "ok"
        voice_ok = voice.get("status") == "ok"
        avatar_ok = avatar.get("status") == "ok" and bool(avatar.get("connected"))

        lines = [
            "ARES status:",
            f"- Perception: {'online' if perception_ok else 'unavailable'}",
            f"- Voice: {'online' if voice_ok else 'unavailable'}",
            f"- Avatar: {'connected' if avatar_ok else 'fallback active'}",
            "- Memory: shared workspace configured",
        ]
        return "\n".join(lines), "speaking", "neutral"

    if len(text) > 30:
        return (
            f"I'm tracking it: '{text[:80]}...'. "
            "I need the full reasoning loop wired before I can give this the depth it deserves."
        ), "thinking", "thinking"

    return f"I heard: '{text}'. I'm listening.", "listening", "curious"


class HermesHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send_json({"status": "ok"})

    def do_GET(self):
        if self.path == "/health":
            self._send_json({
                "status": "ok",
                "uptime": int(time.time() - start_time),
                "version": "bridge-v2",
                "servers": {"perception": 9512, "voice": 9513, "avatar": 9514},
            })
        elif self.path == "/avatar":
            self._send_json(call_mcp(9514, "avatar_state"))
        else:
            self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path != "/think":
            self._send_json({"error": "not found"}, 404)
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 64_000:
                self._send_json({"error": "request too large", "response": "Request too large.", "state": "error", "expression": "concerned"}, 413)
                return
            body = json.loads(self.rfile.read(length)) if length else {}
        except (json.JSONDecodeError, ValueError):
            self._send_json({"error": "invalid json", "response": "Bad request.", "state": "error", "expression": "concerned"}, 400)
            return

        text = body.get("text", "")
        session_id = body.get("session_id", "unknown")

        if not isinstance(text, str) or not text.strip():
            self._send_json({"response": "Empty input.", "state": "error", "expression": "neutral"}, 400)
            return

        response, state, expression = cognition_query(text, session_id)
        if state not in VALID_STATES:
            state = "idle"
        if expression not in VALID_EXPRESSIONS:
            expression = "neutral"
        self._send_json({
            "response": response,
            "state": state,
            "expression": expression,
        })


def serve():
    server = ThreadingHTTPServer((HOST, PORT), HermesHandler)
    print(f"ARES Bridge v2: http://{HOST}:{PORT}")
    print("  GET  /health  - system overview")
    print("  GET  /avatar  - avatar state proxy")
    print("  POST /think   - cognition query")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()


if __name__ == "__main__":
    serve()
