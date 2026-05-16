"""ARES Service Manager — subprocess lifecycle for all background MCP servers.

Manages starting, stopping, and health-checking the MCP skill servers
(perception, voice, avatar) and the cognition bridge.
"""

from __future__ import annotations

import asyncio
import logging
import os
import shutil
import signal as _signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

import httpx

logger = logging.getLogger("ares.runtime.service_manager")

VENV_PYTHON = shutil.which("python3") or sys.executable or "python3"
REPO_ROOT = Path(__file__).resolve().parent.parent.parent  # ARES-Autonomous-Reasoning-Execution-System/

# Shared HTTP client for health checks
_api_client: httpx.AsyncClient | None = None


def _get_api_client() -> httpx.AsyncClient:
    global _api_client
    if _api_client is None:
        _api_client = httpx.AsyncClient()
    return _api_client


class ManagedService:
    """A subprocess-managed service that starts/stops with the FastAPI app."""

    def __init__(self, name: str, port: int, module: str, kind: str = "mcp"):
        self.name = name
        self.port = port
        self.module = module  # Python dotted path (e.g. ares.skills.cognitive.perception_server)
        self.kind = kind  # "mcp", "bridge"
        self.process: Optional[subprocess.Popen] = None
        self.start_time: Optional[float] = None

    def _kill_port_owner(self):
        """Kill any process already listening on our port."""
        try:
            result = subprocess.run(
                ["lsof", "-ti", f":{self.port}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            for pid_str in result.stdout.strip().split("\n"):
                pid = pid_str.strip()
                if pid and pid.isdigit():
                    try:
                        os.kill(int(pid), _signal.SIGTERM)
                        logger.info("%s: killed stale PID %s on :%d", self.name, pid, self.port)
                    except OSError as e:
                        logger.debug("Failed to kill stale PID %s: %s", pid, e)
        except Exception as e:
            logger.warning("lsof/port-kill failed for %s on :%d: %s", self.name, self.port, e)

    async def start(self):
        """Start the service as a subprocess."""
        if self.process is not None and self.process.poll() is None:
            logger.info("%s already running (PID %d)", self.name, self.process.pid)
            return

        # Kill anything already on our port
        self._kill_port_owner()

        # Use python -m for package modules
        cmd = [VENV_PYTHON, "-m", self.module]

        logger.info("Starting %s on :%d — %s", self.name, self.port, " ".join(cmd))
        self.process = subprocess.Popen(
            cmd,
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # merge stderr to stdout for capture
            stdin=subprocess.DEVNULL,
        )
        self.start_time = time.time()

        # Brief wait to check for immediate crash
        await asyncio.sleep(1.5)
        if self.process.poll() is not None:
            out = self.process.stdout.read().decode(errors="replace") if self.process.stdout else ""
            logger.error("%s crashed on start: %s", self.name, out[:500])
        else:
            logger.info("%s started (PID %d)", self.name, self.process.pid)

    def stop(self):
        """Gracefully stop the service."""
        if self.process is None or self.process.poll() is not None:
            return

        logger.info("Stopping %s (PID %d)", self.name, self.process.pid)
        try:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        except Exception as e:
            logger.warning("Error stopping %s: %s", self.name, e)
        self.process = None
        self.start_time = None

    def is_running(self) -> bool:
        """Check if the process is alive."""
        if self.process is None:
            return False
        return self.process.poll() is None

    async def health_check(self) -> dict:
        """Check service health by attempting a connection."""
        result = {
            "name": self.name,
            "port": self.port,
            "kind": self.kind,
            "running": self.is_running(),
            "pid": self.process.pid if self.is_running() else None,
            "uptime": int(time.time() - self.start_time) if self.start_time else 0,
            "reachable": False,
        }

        # TCP check
        if self.is_running():
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                if sock.connect_ex(("127.0.0.1", self.port)) == 0:
                    result["reachable"] = True
                sock.close()
            except Exception as e:
                logger.debug("TCP health check error for %s: %s", self.name, e)

        # HTTP health check for bridge
        if self.kind == "bridge" and result["reachable"]:
            try:
                client = _get_api_client()
                resp = await client.get(
                    f"http://127.0.0.1:{self.port}/health",
                    timeout=5.0,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    result["health_response"] = data
            except Exception:
                result["health_response_error"] = "unreachable"

        return result


# ---------------------------------------------------------------------------
# Default services
# ---------------------------------------------------------------------------

SERVICES = [
    ManagedService(
        name="perception",
        port=9512,
        module="ares.skills.cognitive.perception_server",
        kind="mcp",
    ),
    ManagedService(
        name="voice",
        port=9513,
        module="ares.skills.cognitive.voice_server",
        kind="mcp",
    ),
    ManagedService(
        name="avatar",
        port=9514,
        module="ares.skills.cognitive.avatar_server",
        kind="mcp",
    ),
    ManagedService(
        name="cad",
        port=9515,
        module="ares.skills.physical.cad_server",
        kind="mcp",
    ),
    ManagedService(
        name="simulation",
        port=9516,
        module="ares.skills.physical.simulation_server",
        kind="mcp",
    ),
    ManagedService(
        name="generation",
        port=9517,
        module="ares.skills.physical.generation_server",
        kind="mcp",
    ),
    ManagedService(
        name="motor",
        port=9519,
        module="ares.skills.physical.motor_server",
        kind="mcp",
    ),
    ManagedService(
        name="cognition_bridge",
        port=9876,
        module="ares.runtime.hermes_backend",
        kind="bridge",
    ),
]
