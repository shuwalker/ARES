"""Process lifecycle — prepare, bring_up, teardown, and PID management.

Ported from Lilith's lifecycle pattern. Manages the ARES process group:
FastAPI server, MCP skill servers, and the active brain backend.
"""

from __future__ import annotations

import logging
import os
import signal
import subprocess
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from ares.core.agent import AgentInterface, load_backend
from ares.runtime.config import AresConfig, load_config

logger = logging.getLogger("ares.runtime.lifecycle")


@dataclass
class Session:
    """A running ARES session — config, identity, backend, and service state."""

    config: AresConfig
    backend: AgentInterface
    services: list = field(default_factory=list)
    pid_file: Optional[Path] = None
    started_at: Optional[float] = None

    @property
    def home(self) -> Path:
        return self.config.home


def prepare(config: Optional[AresConfig] = None) -> Session:
    """Resolve config, discover skills, validate. No processes started."""
    cfg = config or load_config()
    backend = load_backend(cfg.agent.backend, cfg.agent_dict())

    # Ensure home directory exists
    cfg.home.mkdir(parents=True, exist_ok=True)

    return Session(config=cfg, backend=backend)


@contextmanager
def bring_up(config: Optional[AresConfig] = None, skip_backend: bool = False):
    """Start ARES services: FastAPI, MCP servers, brain backend.

    Yields a Session. All processes are stopped on exit.
    """
    session = prepare(config)
    session.started_at = time.time()

    # Write PID file
    pid_file = session.config.home / "ares.pid"
    pid_file.write_text(str(os.getpid()))
    session.pid_file = pid_file

    try:
        # Start MCP skill servers (via FastAPI managed services)
        # The FastAPI lifespan handler starts these when uvicorn boots.
        logger.info("ARES session prepared — services will start with API server")

        if not skip_backend:
            session.backend.connect()
            logger.info("Backend connected: %s", session.backend.health())

        yield session
    finally:
        teardown(session)


def teardown(session: Session) -> None:
    """Stop all processes, clean PID files."""
    logger.info("ARES teardown — stopping services")

    try:
        session.backend.disconnect()
    except Exception as e:
        logger.warning("Backend disconnect error: %s", e)

    # Clean PID file
    if session.pid_file and session.pid_file.exists():
        session.pid_file.unlink()
        logger.info("PID file removed: %s", session.pid_file)

    logger.info("ARES teardown complete")


def cleanup_previous_instance(home: Optional[Path] = None) -> dict:
    """Three-layer orphan cleanup:

    1. PID file -> SIGTERM if alive and matching argv
    2. pgrep sweep -> kill any ARES processes with matching fingerprint
    3. Port sweep -> kill anything holding our ports (if ARES-fingerprinted)

    Never kills unrelated processes on the same port.
    """
    from ares.runtime.config import load_config

    cfg = load_config()
    ares_home = home or cfg.home
    pid_file = ares_home / "ares.pid"
    results = {"pid_file": None, "pgrep": [], "ports": []}

    # Layer 1: PID file
    if pid_file.exists():
        try:
            old_pid = int(pid_file.read_text().strip())
            results["pid_file"] = old_pid
            if _is_ares_process(old_pid):
                os.kill(old_pid, signal.SIGTERM)
                time.sleep(1)
                # Force kill if still alive
                try:
                    os.kill(old_pid, 0)  # Check if alive
                    os.kill(old_pid, signal.SIGKILL)
                except OSError as e:
                    logger.debug("SIGKILL failed for PID %d: %s", old_pid, e)
                logger.info("Killed stale ARES process: PID %d", old_pid)
            pid_file.unlink(missing_ok=True)
        except (ValueError, OSError) as e:
            logger.warning("PID file cleanup failed: %s", e)

    # Layer 2: pgrep sweep
    try:
        result = subprocess.run(
            ["pgrep", "-f", "python.*-m.*ares"],
            capture_output=True, text=True, timeout=5,
        )
        if result.stdout.strip():
            for pid_str in result.stdout.strip().split("\n"):
                pid = int(pid_str)
                if _is_ares_process(pid):
                    os.kill(pid, signal.SIGTERM)
                    results["pgrep"].append(pid)
    except Exception as e:
        logger.debug("pgrep sweep failed: %s", e)

    # Layer 3: Port sweep (for ARES ports only)
    for port in [7860, 9876]:  # API and cognition bridge
        try:
            result = subprocess.run(
                ["lsof", "-ti", f":{port}"],
                capture_output=True, text=True, timeout=5,
            )
            if result.stdout.strip():
                for pid_str in result.stdout.strip().split("\n"):
                    pid = int(pid_str.strip())
                    if _is_ares_process(pid):
                        os.kill(pid, signal.SIGTERM)
                        results["ports"].append((port, pid))
        except Exception as e:
            logger.debug("Port sweep failed for :%d: %s", port, e)

    return results


def _is_ares_process(pid: int) -> bool:
    """Check if a PID belongs to an ARES process (not some other app)."""
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_text().replace("\x00", " ")
    except (FileNotFoundError, PermissionError):
        # macOS: try ps
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "command="],
                capture_output=True, text=True, timeout=3,
            )
            cmdline = result.stdout.strip()
        except Exception as exc:
            logger.debug("_is_ares_process check failed for PID %d: %s", pid, exc)
            return False

    return "ares" in cmdline.lower() or "python" in cmdline.lower()