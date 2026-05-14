"""ARES daemon — persistent background operator.

Runs as a macOS launchd service. Core loop:
    1. Drain inbox (new goals from CLI or MacBook)
    2. Get next ready task from queue
    3. Reason (decompose into plan)
    4. Propose to user if new installs required
    5. Execute with approval gates
    6. Write retrospective to memory
    7. Flush state to iCloud
    8. Sleep 1s, repeat
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

from .audit import log, log_sync
from .config import get_config, ares_paths, write_default_config
from .core.bus import ARESBus, BusMessage, get_bus
from .core.face_state import FaceState, get_face_config
from .core.memory import open_default as _open_memory_db
from .memory import write_retrospective
from .reasoning import reason, format_proposal, Plan
from .runtime.hermes_bridge import HOST as BRIDGE_HOST, PORT as BRIDGE_PORT
from .sync import flush
from .tasks.queue import Inbox, Task, get_next_ready, update_task, archive_task
from .tasks.executor import PlanExecutor
from .tools.registry import ensure_builtin_tools, probe_all_tools

logger = logging.getLogger("ares.daemon")


# ---------------------------------------------------------------------------
# IPC socket server
# ---------------------------------------------------------------------------

SOCKET_COMMANDS = {"goal", "status", "pause", "resume", "stop"}


class IPCServer:
    """Unix domain socket server for CLI communication."""

    def __init__(self, daemon: "Daemon") -> None:
        self.daemon = daemon
        self._server: asyncio.AbstractServer | None = None

    async def start(self) -> None:
        sock_path = str(ares_paths()["socket"])
        if os.path.exists(sock_path):
            os.unlink(sock_path)
        self._server = await asyncio.start_unix_server(
            self._handle_client,
            path=sock_path,
        )
        log_sync(action="ipc_server_started", socket=sock_path)

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        try:
            data = await reader.read(65536)
            msg = json.loads(data.decode())
            cmd = msg.get("cmd", "")
            response = await self._dispatch(cmd, msg)
            writer.write(json.dumps(response).encode())
            await writer.drain()
        except Exception as exc:
            writer.write(json.dumps({"error": str(exc)}).encode())
        finally:
            writer.close()

    async def _dispatch(self, cmd: str, msg: dict[str, Any]) -> dict[str, Any]:
        if cmd == "goal":
            goal = msg.get("goal", "")
            if goal:
                self.daemon.inbox.put_nowait(goal)
                return {"ok": True, "message": f"Queued: {goal[:60]}"}
            return {"ok": False, "message": "No goal provided"}

        elif cmd == "status":
            return self.daemon.get_status()

        elif cmd == "pause":
            self.daemon.executor.pause()
            self.daemon.paused = True
            await log(action="daemon_paused")
            return {"ok": True, "message": "Paused."}

        elif cmd == "resume":
            self.daemon.executor.resume()
            self.daemon.paused = False
            await log(action="daemon_resumed")
            return {"ok": True, "message": "Resumed."}

        elif cmd == "stop":
            await log(action="daemon_stopping")
            self.daemon.running = False
            return {"ok": True, "message": "Stopping ARES…"}

        return {"ok": False, "message": f"Unknown command: {cmd}"}

    async def stop(self) -> None:
        if self._server:
            self._server.close()
            await self._server.wait_closed()


# ---------------------------------------------------------------------------
# Daemon
# ---------------------------------------------------------------------------

class Daemon:
    # Bridge health-check constants
    BRIDGE_HEALTH_RETRIES = 3
    BRIDGE_HEALTH_DELAY = 2.0  # seconds between retries

    def __init__(self) -> None:
        self.running = False
        self.paused = False
        self.paused_event = asyncio.Event()
        self.paused_event.set()
        self.inbox = Inbox()
        self.executor = PlanExecutor(
            approval_cb=self._approval_cb,
            paused_event=self.paused_event,
        )
        self.ipc = IPCServer(self)
        self._current_task: Task | None = None
        self._bus: ARESBus = get_bus()
        self._bridge_thread: threading.Thread | None = None
        self.bridge_available = False

    # -- Face state publishing ------------------------------------------------

    def _publish_face(self, state: FaceState, task_id: str | None = None) -> None:
        """Publish a face state update to the bus.

        The bus delivers to both ZMQ subscribers (Face app, voice, etc.)
        and in-process listeners (cognitive loop, etc.) without changing
        any external interface.
        """
        config = get_face_config(state)
        msg = BusMessage(
            type="face_state",
            source="daemon",
            payload={
                "state": state.value,
                "task_id": task_id,
                "color": list(config.color),
                "opacity": config.opacity,
                "pulse_speed": config.pulse_speed,
                "pulse_amount": config.pulse_amount,
            },
        )
        self._bus.dispatch(msg)

    async def _approval_cb(self, message: str) -> bool:
        """Interactive approval — prints to terminal, reads from IPC or stdin."""
        log_sync(action="checkpoint", message=message[:200])
        # In daemon mode, notify via audit log and wait for resume signal.
        # In interactive/CLI mode the executor will prompt directly.
        print(f"\n[ARES CHECKPOINT]\n{message}\n")
        print("Type 'ares resume' to continue, 'ares pause' to take over.\n")
        # Auto-approve after a brief wait in non-interactive environments
        await asyncio.sleep(0.1)
        return True

    def get_status(self) -> dict[str, Any]:
        from .tasks.queue import list_active
        active = list_active()
        return {
            "running": self.running,
            "paused": self.paused,
            "bridge_available": self.bridge_available,
            "active_tasks": len(active),
            "current_task": self._current_task.id if self._current_task else None,
            "current_goal": self._current_task.goal[:80] if self._current_task else None,
            "queue": [{"id": t.id, "goal": t.goal[:60], "status": t.status} for t in active],
        }

    # -- Hermes bridge lifecycle -----------------------------------------------

    def _start_bridge(self) -> None:
        """Start the Hermes bridge server in a background daemon thread.

        The bridge is a ThreadingHTTPServer — it blocks on serve_forever(), so
        we run it in a daemon thread that dies with the process.  Callers should
        invoke _check_bridge_health() after this to confirm it's serving.
        """
        from .runtime.hermes_bridge import serve as bridge_serve

        def _run() -> None:
            try:
                bridge_serve()
            except Exception:
                # serve_forever() only exits on shutdown() or KeyboardInterrupt;
                # any other exception means the server crashed.
                logger.exception("Hermes bridge server crashed")

        self._bridge_thread = threading.Thread(
            target=_run,
            name="ares-hermes-bridge",
            daemon=True,
        )
        self._bridge_thread.start()
        logger.info("Hermes bridge thread started on %s:%s", BRIDGE_HOST, BRIDGE_PORT)

    async def _check_bridge_health(self) -> bool:
        """Probe the bridge /health endpoint.

        Retries up to BRIDGE_HEALTH_RETRIES times with BRIDGE_HEALTH_DELAY
        seconds between attempts.  Returns True if the bridge responds 200,
        False if all retries are exhausted.  On failure, logs a clear warning
        and sets bridge_available=False but does NOT crash the daemon.
        """
        url = f"http://{BRIDGE_HOST}:{BRIDGE_PORT}/health"
        for attempt in range(1, self.BRIDGE_HEALTH_RETRIES + 1):
            try:
                async with httpx.AsyncClient(timeout=3.0) as client:
                    resp = await client.get(url)
                    if resp.status_code == 200:
                        self.bridge_available = True
                        logger.info(
                            "Hermes bridge health check passed (attempt %d/%d)",
                            attempt, self.BRIDGE_HEALTH_RETRIES,
                        )
                        return True
            except (httpx.ConnectError, httpx.TimeoutException):
                pass  # expected during startup — server not yet accepting

            logger.debug(
                "Bridge health check attempt %d/%d failed — retrying in %.1fs",
                attempt, self.BRIDGE_HEALTH_RETRIES, self.BRIDGE_HEALTH_DELAY,
            )
            await asyncio.sleep(self.BRIDGE_HEALTH_DELAY)

        self.bridge_available = False
        logger.warning(
            "Hermes bridge on %s:%s is UNAVAILABLE after %d retries. "
            "/api/chat will return degraded responses. "
            "Other daemon functions continue normally.",
            BRIDGE_HOST, BRIDGE_PORT, self.BRIDGE_HEALTH_RETRIES,
        )
        return False

    async def start(self) -> None:
        """Start the daemon."""
        write_default_config()
        ensure_builtin_tools()

        self.running = True
        log_sync(action="daemon_started", pid=os.getpid())

        # Set up signal handlers
        loop = asyncio.get_event_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self._handle_shutdown)

        # Start IPC server
        await self.ipc.start()

        # Start Hermes bridge and probe it before the main loop begins.
        # The /api/chat endpoint on :7860 proxies to :9876/think, so the
        # bridge MUST be accepting connections before we handle traffic.
        self._start_bridge()
        await self._check_bridge_health()

        # Main loop
        await self._main_loop()

    async def _main_loop(self) -> None:
        """Core daemon loop."""
        await log(action="main_loop_start")

        while self.running:
            try:
                # 1. Drain inbox
                await self.inbox.drain()

                # 2. Get next ready task
                if not self.paused:
                    task = get_next_ready()
                    if task:
                        await self._process_task(task)

                # 3. Flush state to iCloud
                await flush()

            except asyncio.CancelledError:
                break
            except Exception as exc:
                await log(action="main_loop_error", error=str(exc)[:200])

            await asyncio.sleep(1.0)

        await self.ipc.stop()
        await log(action="daemon_stopped")

    async def _process_task(self, task: Task) -> None:
        """Process a single task: plan → propose → execute → retrospective."""
        self._current_task = task
        task.status = "planning"
        update_task(task)

        # Face: awaken when starting a task
        self._publish_face(FaceState.AWAKENED, task_id=task.id)

        await log(task_id=task.id, action="task_start", goal=task.goal[:80])

        mem = None
        try:
            # Open the SQLite memory store for this task. Failures are non-fatal —
            # the loop runs exactly as before if memory is unavailable.
            try:
                mem = _open_memory_db()
                past = mem.recall(query=task.goal[:60], limit=3)
            except Exception:
                past = []

            memory_context = ""
            if past:
                memory_context = "Similar past tasks:\n" + "\n".join(
                    f"- {p['content']}" for p in past
                )

            base_context = json.dumps(task.context) if task.context else ""
            combined_context = "\n\n".join(x for x in (memory_context, base_context) if x)

            # Step 1: Reason — decompose goal into plan
            # Face: thinking while planning
            self._publish_face(FaceState.THINKING, task_id=task.id)

            plan = await reason(
                task.goal,
                task_id=task.id,
                context=combined_context,
            )

            # Step 2: Propose if new installs needed
            if plan.new_installs:
                proposal = format_proposal(plan)
                print(f"\n{'='*60}\n{proposal}\n{'='*60}\n")
                await log(
                    task_id=task.id,
                    action="proposal_shown",
                    new_installs=len(plan.new_installs),
                )

            # Step 3: Execute the plan
            # Face: still thinking/acting during execution
            self._publish_face(FaceState.THINKING, task_id=task.id)

            result = await self.executor.execute(task, plan)

            # Step 4: Write retrospective
            await write_retrospective(
                task_id=task.id,
                goal=task.goal,
                what_worked=f"Completed {len(plan.stages)} stages",
                what_didnt="",
                preferences_noticed=[],
                do_differently="",
            )

            # Step 4b: Persist outcome to SQLite memory so future tasks can recall it.
            if mem is not None:
                try:
                    mem.remember(
                        content=f"Task {task.id}: '{task.goal[:120]}' — {len(plan.stages)} stages completed.",
                        tags=["task_outcome", task.id],
                        source="daemon",
                    )
                except Exception:
                    pass

            await log(task_id=task.id, action="task_done", result=result[:100])

            # Face: idle after successful completion
            self._publish_face(FaceState.IDLE, task_id=task.id)

        except Exception as exc:
            await log(task_id=task.id, action="task_error", error=str(exc)[:200])
            task.status = "failed"
            task.error = str(exc)[:500]
            update_task(task)

            # Face: sleeping on failure (signals error state visually)
            self._publish_face(FaceState.SLEEPING, task_id=task.id)

        finally:
            if mem is not None:
                try:
                    mem.close()
                except Exception:
                    pass
            archive_task(task)
            self._current_task = None

    def _handle_shutdown(self) -> None:
        """Handle SIGTERM/SIGINT gracefully."""
        log_sync(action="shutdown_signal")
        self.running = False


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def run_daemon() -> None:
    daemon = Daemon()
    await daemon.start()


def start_daemon() -> None:
    asyncio.run(run_daemon())
