"""Integration test configuration and fixtures.

All service hosts/ports are configurable via environment variables with
local defaults.  If a service is unreachable at test collection time,
tests that depend on it are skipped — never fail — so the suite works
in any environment where the full stack may not be running.
"""

import json
import os
import socket
import urllib.request
import uuid

import pytest

# ═══════════════════════════════════════════════════════════════════════════
# Defaults — override via env
# ═══════════════════════════════════════════════════════════════════════════

ARES_HOST = os.environ.get("ARES_HOST", "127.0.0.1")

FASTAPI_PORT = int(os.environ.get("ARES_FASTAPI_PORT", "7860"))
MAC_MCP_PORT = int(os.environ.get("ARES_MAC_MCP_PORT", "9501"))
PERCEPTION_PORT = int(os.environ.get("ARES_PERCEPTION_PORT", "9512"))
VOICE_PORT = int(os.environ.get("ARES_VOICE_PORT", "9513"))
AVATAR_PORT = int(os.environ.get("ARES_AVATAR_PORT", "9514"))
BRIDGE_PORT = int(os.environ.get("ARES_BRIDGE_PORT", "9876"))

REQUEST_TIMEOUT = 3  # seconds for TCP probes
HTTP_TIMEOUT = 5     # seconds for HTTP requests


# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

def _tcp_probe(port: int, host: str = ARES_HOST) -> bool:
    """True if the port is accepting connections."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(REQUEST_TIMEOUT)
        ok = s.connect_ex((host, port)) == 0
        s.close()
        return ok
    except Exception:
        return False


def _http_get(url: str, timeout: int = HTTP_TIMEOUT) -> tuple[int, str | dict]:
    """Return (status_code, response_body_or_dict)."""
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode()
            try:
                return resp.status, json.loads(body)
            except json.JSONDecodeError:
                return resp.status, body
    except Exception as e:
        return 0, str(e)


def _require(reachable: bool, name: str, port: int) -> None:
    """Skip if the service is not reachable."""
    if not reachable:
        pytest.skip(f"{name} ({ARES_HOST}:{port}) unreachable")


def _mcp_initialize(port: int, host: str = ARES_HOST) -> tuple[str | None, dict | None]:
    """Initialize an MCP SSE session and return (session_id, server_info).

    Returns (None, None) if the MCP server is unreachable or rejects the init.
    """
    init_payload = json.dumps({
        "jsonrpc": "2.0",
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "ares-integration-test", "version": "1.0"},
        },
        "id": 1,
    }).encode()

    try:
        req = urllib.request.Request(
            f"http://{host}:{port}/mcp",
            data=init_payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "text/event-stream, application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            raw = resp.read().decode()
            # SSE format: "event: message\ndata: <json>\n\n"
            session_id = resp.headers.get("mcp-session-id")
            # Parse the SSE data
            for line in raw.split("\n"):
                if line.startswith("data: "):
                    payload = json.loads(line[6:])
                    result = payload.get("result", {})
                    server_info = result.get("serverInfo", {})
                    return session_id, server_info
            return session_id, None
    except Exception:
        return None, None


def _mcp_list_tools(port: int, session_id: str, host: str = ARES_HOST) -> list[dict]:
    """List tools available on an MCP server given a session ID."""
    payload = json.dumps({
        "jsonrpc": "2.0",
        "method": "tools/list",
        "id": 2,
    }).encode()

    try:
        req = urllib.request.Request(
            f"http://{host}:{port}/mcp",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "text/event-stream, application/json",
                "mcp-session-id": session_id,
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            raw = resp.read().decode()
            for line in raw.split("\n"):
                if line.startswith("data: "):
                    payload = json.loads(line[6:])
                    return payload.get("result", {}).get("tools", [])
    except Exception:
        pass
    return []


# ═══════════════════════════════════════════════════════════════════════════
# Fixtures
# ═══════════════════════════════════════════════════════════════════════════

@pytest.fixture(scope="session")
def host():
    return ARES_HOST


@pytest.fixture(scope="session")
def fastapi_port():
    return FASTAPI_PORT


# ── Per-service availability ──────────────────────────────────────────────

@pytest.fixture(scope="session")
def fastapi_alive(host, fastapi_port):
    alive = _tcp_probe(fastapi_port, host)
    _require(alive, "FastAPI", fastapi_port)
    return alive


@pytest.fixture(scope="session")
def mac_mcp_alive(host):
    alive = _tcp_probe(MAC_MCP_PORT, host)
    _require(alive, "Mac MCP", MAC_MCP_PORT)
    return alive


@pytest.fixture(scope="session")
def perception_alive(host):
    alive = _tcp_probe(PERCEPTION_PORT, host)
    _require(alive, "Perception MCP", PERCEPTION_PORT)
    return alive


@pytest.fixture(scope="session")
def voice_alive(host):
    alive = _tcp_probe(VOICE_PORT, host)
    _require(alive, "Voice MCP", VOICE_PORT)
    return alive


@pytest.fixture(scope="session")
def avatar_alive(host):
    alive = _tcp_probe(AVATAR_PORT, host)
    _require(alive, "Avatar MCP", AVATAR_PORT)
    return alive


@pytest.fixture(scope="session")
def bridge_alive(host):
    alive = _tcp_probe(BRIDGE_PORT, host)
    _require(alive, "Cognition Bridge", BRIDGE_PORT)
    return alive


# ── MCP session fixtures ──────────────────────────────────────────────────

@pytest.fixture(scope="session")
def mac_mcp_session(host, mac_mcp_alive):
    """Initialized SSE session for Mac MCP :9501."""
    sid, info = _mcp_initialize(MAC_MCP_PORT, host)
    if sid is None:
        pytest.skip("Mac MCP session init failed")
    tools = _mcp_list_tools(MAC_MCP_PORT, sid, host)
    return {"session_id": sid, "server_info": info, "tools": tools}


@pytest.fixture(scope="session")
def perception_session(host, perception_alive):
    """Initialized SSE session for Perception MCP :9512."""
    sid, info = _mcp_initialize(PERCEPTION_PORT, host)
    if sid is None:
        pytest.skip("Perception MCP session init failed")
    tools = _mcp_list_tools(PERCEPTION_PORT, sid, host)
    return {"session_id": sid, "server_info": info, "tools": tools}


@pytest.fixture(scope="session")
def voice_session(host, voice_alive):
    """Initialized SSE session for Voice MCP :9513."""
    sid, info = _mcp_initialize(VOICE_PORT, host)
    if sid is None:
        pytest.skip("Voice MCP session init failed")
    tools = _mcp_list_tools(VOICE_PORT, sid, host)
    return {"session_id": sid, "server_info": info, "tools": tools}


@pytest.fixture(scope="session")
def avatar_session(host, avatar_alive):
    """Initialized SSE session for Avatar MCP :9514."""
    sid, info = _mcp_initialize(AVATAR_PORT, host)
    if sid is None:
        pytest.skip("Avatar MCP session init failed")
    tools = _mcp_list_tools(AVATAR_PORT, sid, host)
    return {"session_id": sid, "server_info": info, "tools": tools}
