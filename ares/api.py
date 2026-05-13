"""ARES API Server — FastAPI bridge between Python brain and Swift face.

This is the web layer that lets the SwiftUI app talk to ARES's Python core.
It manages the lifecycle of all MCP servers (perception, voice, avatar) and
the cognition bridge, exposing a unified /api/services health endpoint.

Managed services (all started/stopped with the FastAPI app):
    :7860  — FastAPI (this process)
    :9512  — Perception MCP (YOLOv8n + Florence-2)
    :9513  — Voice MCP (STT + TTS)
    :9514  — Avatar MCP (VTube Studio)
    :9876  — Hermes cognition bridge

REST endpoints:
    GET  /api/status           — system status
    GET  /api/services         — health of all 6 services
    GET  /api/identity         — who ARES is
    GET  /api/personality       — 4-layer personality profile
    POST /api/personality       — set a personality trait
    GET  /api/face              — current face state
    POST /api/face              — set face state or emotion
    POST /api/chat              — send a message, get a response
    POST /api/memory            — store a fact
    GET  /api/memory            — search memory

WebSocket:
    WS   /ws                    — real-time stream
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import subprocess
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import httpx

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from ares.core.bus import ARESBus, BusMessage, get_bus
from ares.core.cognitive import CognitiveLoop, create_loop
from ares.core.idle import IdleReport, run_idle_pass
from ares.core.face_state import FaceState, get_face_config, emotion_to_face_state
from ares.core.identity import Identity, DEFAULT_IDENTITY
from ares.core.personality import CharacterProfile, DEFAULT_PROFILE, load_personality, save_personality
from ares.memory_store import MemoryStore, default_memory_store
from ares.models.cognitive import (
    CognitiveSnapshot,
    LoopBlock,
    MemoryHitBlock,
    ThoughtBlock,
    ThoughtNode,
)
from ares.runtime.session_store import SessionStore

logger = logging.getLogger("ares.api")

# Global cognitive loop reference
_cognitive_loop: Optional[CognitiveLoop] = None

# ---------------------------------------------------------------------------
# Service Manager — subprocess lifecycle for all background servers
# ---------------------------------------------------------------------------

VENV_PYTHON = "/Users/matthewjenkins/.hermes/hermes-agent/venv/bin/python"
REPO_ROOT = Path(__file__).resolve().parent.parent  # ARES-Autonomous-Reasoning-Execution-System/


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
        import signal as _signal
        try:
            result = subprocess.run(
                ["lsof", "-ti", f":{self.port}"],
                capture_output=True, text=True, timeout=5,
            )
            for pid_str in result.stdout.strip().split("\n"):
                pid = pid_str.strip()
                if pid and pid.isdigit():
                    try:
                        os.kill(int(pid), _signal.SIGTERM)
                        logger.info("%s: killed stale PID %s on :%d", self.name, pid, self.port)
                    except OSError:
                        pass
        except Exception:
            pass

    def start(self):
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
        time.sleep(1.5)
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
        import socket

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
            except Exception:
                pass

        # HTTP health check for bridge
        if self.kind == "bridge" and result["reachable"]:
            try:
                async with httpx.AsyncClient(timeout=5) as client:
                    resp = await client.get(f"http://127.0.0.1:{self.port}/health")
                    if resp.status_code == 200:
                        data = resp.json()
                        result["health_response"] = data
            except Exception:
                result["health_response_error"] = "unreachable"

        return result


# Define all managed services
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
        name="cognition_bridge",
        port=9876,
        module="ares.runtime.hermes_bridge",
        kind="bridge",
    ),
]


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class PersonalityUpdateRequest(BaseModel):
    layer: str = Field(..., description="hexaco, special, expression, or domains")
    trait: str = Field(..., description="Trait name within the layer")
    value: float = Field(..., ge=0.0, le=1.0, description="Value 0.0-1.0")


class PersonalityUpdateResponse(BaseModel):
    updated: bool
    layer: str
    trait: str
    value: float


class FaceStateRequest(BaseModel):
    state: Optional[str] = Field(None, description="Face state: idle, awakened, listening, thinking, speaking, sleeping")
    emotion: Optional[str] = Field(None, description="Emotion: happy, sad, curious, surprised, angry, neutral")


class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    response: str
    face_state: str
    personality_prompt: Optional[str] = None


class MemoryStoreRequest(BaseModel):
    content: str
    tags: Optional[str] = None
    source: str = "api"


class MemorySearchRequest(BaseModel):
    query: str
    tag: Optional[str] = None
    limit: int = 10


# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------

def create_app(
    bus: ARESBus = None,
    personality: CharacterProfile = None,
    memory: MemoryStore = None,
    sessions: SessionStore = None,
) -> FastAPI:
    """Create the ARES FastAPI application with managed service lifecycle.

    `memory` and `sessions` are injectable so tests can bypass disk I/O.
    """

    bus = bus or get_bus()
    personality = personality or load_personality()
    memory = memory if memory is not None else default_memory_store()
    sessions = sessions if sessions is not None else SessionStore(capacity=12)
    websocket_clients: set = set()
    # Tracks the last snapshot delivered to clients — used by /api/chat to
    # include memory hits in the next push without re-querying twice.
    _last_recall: list[MemoryHitBlock] = []
    # Last idle reflexion report, served by /api/idle/last_report so the
    # UI can surface "open questions" and "summary facts written".
    _last_idle_report: dict = {}

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        """Start all managed services on startup, stop them on shutdown."""
        global _cognitive_loop

        # ── Startup ──────────────────────────────────────────────────
        logger.info("ARES API starting — initializing all services")
        bus.start_heartbeat(interval_sec=5.0, source="ares_api")

        # Start all MCP servers + bridge
        for svc in SERVICES:
            svc.start()

        # Initialize face state
        _save_face_state({"current_state": "idle", "state": "idle"})

        # Connect to cognition bus
        bus.on("face_state", _on_face_state)

        logger.info("ARES API ready — all services launched")
        yield

        # ── Shutdown ─────────────────────────────────────────────────
        logger.info("ARES API shutting down — stopping all services")
        if _cognitive_loop is not None:
            _cognitive_loop.stop()

        for svc in SERVICES:
            svc.stop()

        bus.stop()
        logger.info("ARES API shutdown complete")

    app = FastAPI(
        title="ARES API",
        version="0.1.0",
        description="Autonomous Reasoning & Execution System — brain API",
        lifespan=lifespan,
    )

    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:*", "http://127.0.0.1:*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ------------------------------------------------------------------
    # REST endpoints
    # ------------------------------------------------------------------

    @app.get("/api/status")
    async def get_status():
        """Get ARES system status."""
        identity = DEFAULT_IDENTITY
        face_data = _load_face_state()
        bus_status = bus.status()
        return {
            "name": identity.name,
            "version": "0.1.0",
            "face_state": face_data.get("current_state", "unknown"),
            "bus": bus_status,
            "websocket_clients": len(websocket_clients),
            "uptime": time.time(),
        }

    @app.get("/api/services")
    async def get_services():
        """Get health status of all ARES services.

        Returns a combined report for all 6 services:
          - FastAPI (this process)
          - Perception MCP :9512
          - Voice MCP :9513
          - Avatar MCP :9514
          - Cognition bridge :9876
          - Mac MCP :9501 (external, check-only)
        """
        # Check external Mac MCP first
        import socket
        mac_mcp = {
            "name": "mac_mcp",
            "port": 9501,
            "kind": "mcp_external",
            "running": True,  # managed independently
            "pid": None,
            "uptime": 0,
            "reachable": False,
        }
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            if sock.connect_ex(("127.0.0.1", 9501)) == 0:
                mac_mcp["reachable"] = True
            sock.close()
        except Exception:
            pass

        # Check all managed services
        managed_checks = [await svc.health_check() for svc in SERVICES]

        # FastAPI self-check
        fastapi_status = {
            "name": "fastapi",
            "port": 7860,
            "kind": "api",
            "running": True,
            "pid": os.getpid(),
            "uptime": int(time.time() - getattr(app.state, "start_time", time.time())),
            "reachable": True,
        }

        all_services = [fastapi_status] + managed_checks + [mac_mcp]

        return {
            "status": "ok",
            "timestamp": time.time(),
            "total": len(all_services),
            "healthy": sum(1 for s in all_services if s.get("reachable")),
            "services": all_services,
        }

    @app.get("/api/identity")
    async def get_identity():
        """Get ARES's identity — name, role, voice, self-model."""
        identity = DEFAULT_IDENTITY
        return {
            "name": identity.name,
            "role": identity.role,
            "voice": identity.voice,
            "self_model": identity.self_model,
        }

    @app.get("/api/personality")
    async def get_personality():
        """Get the full 4-layer personality profile."""
        return personality.to_dict()

    @app.post("/api/personality", response_model=PersonalityUpdateResponse)
    async def set_personality(req: PersonalityUpdateRequest):
        """Set a personality trait (0.0-1.0)."""
        pdata = personality.to_dict()
        if req.layer not in pdata:
            raise HTTPException(400, f"Unknown layer: {req.layer}. Must be one of: {list(pdata.keys())}")
        if req.trait not in pdata[req.layer]:
            raise HTTPException(400, f"Unknown trait: {req.trait} in {req.layer}. Available: {list(pdata[req.layer].keys())}")

        setattr(getattr(personality, req.layer), req.trait, round(req.value, 2))
        save_personality(personality)

        await _broadcast(websocket_clients, {
            "type": "personality_change",
            "layer": req.layer,
            "trait": req.trait,
            "value": req.value,
        })

        return PersonalityUpdateResponse(updated=True, layer=req.layer, trait=req.trait, value=req.value)

    @app.get("/api/face")
    async def get_face_state():
        """Get current face state and all state configurations."""
        return _load_face_state()

    @app.post("/api/face")
    async def set_face_state(req: FaceStateRequest):
        """Set face state or emotion."""
        if req.state:
            try:
                new_state = FaceState(req.state)
            except ValueError:
                valid = [s.value for s in FaceState]
                raise HTTPException(400, f"Invalid state: {req.state}. Valid: {valid}")
            config = get_face_config(new_state)
            result = {
                "state": new_state.value,
                "config": {
                    "color": list(config.color),
                    "opacity": config.opacity,
                    "pulse_speed": config.pulse_speed,
                    "pulse_amount": config.pulse_amount,
                    "pupil_offset": list(config.pupil_offset),
                },
            }
        elif req.emotion:
            new_state = emotion_to_face_state(req.emotion)
            config = get_face_config(new_state)
            result = {
                "emotion": req.emotion,
                "state": new_state.value,
                "config": {
                    "color": list(config.color),
                    "opacity": config.opacity,
                    "pulse_speed": config.pulse_speed,
                    "pulse_amount": config.pulse_amount,
                    "pupil_offset": list(config.pupil_offset),
                },
            }
        else:
            return _load_face_state()

        _save_face_state(result)
        bus.dispatch(BusMessage(type="face_state", source="api", payload=result))
        await _broadcast(websocket_clients, {"type": "face_state", **result})
        return result

    @app.post("/api/chat", response_model=ChatResponse)
    async def chat(req: ChatRequest):
        """Send a message to ARES and get a response via Hermes cognition bridge."""
        personality_prompt = personality.to_system_prompt()

        # Pull relevant episodic memory before dispatch. The Hermes wiring
        # work will eventually consume this to inject context into the LLM
        # prompt; for now we surface it to the UI snapshot so users can
        # see what ARES is recalling.
        hits = memory.recall(req.message, k=5)
        recall_blocks = [
            MemoryHitBlock(id=h.id, score=h.score, text=h.text, kind=h.kind)
            for h in hits
        ]
        _last_recall.clear()
        _last_recall.extend(recall_blocks)

        if req.session_id:
            sessions.record(req.session_id, "user", req.message, time.time())

        bus.dispatch(BusMessage(
            type="chat_message",
            source="api",
            payload={"message": req.message, "session_id": req.session_id},
        ))

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                resp = await client.post(
                    "http://127.0.0.1:9876/think",
                    json={"text": req.message},
                )
                resp.raise_for_status()
                data = resp.json()
                hermes_response = data.get("response", "")
                face_state = data.get("expression", "speaking")
        except Exception as e:
            logger.error("Hermes bridge unreachable: %s", e)
            hermes_response = f"[ARES bridge error — {e}]"
            face_state = "thinking"

        # Persist the exchange. Episodic captures both turns as a single
        # entry so recall can pull the full context; session store tracks
        # turn-by-turn for the volatile tier.
        try:
            memory.record_episodic(
                f"USER: {req.message}\nARES: {hermes_response}",
                metadata={"session_id": req.session_id, "kind": "exchange"},
            )
        except Exception as e:
            logger.warning("Episodic write failed: %s", e)
        if req.session_id:
            sessions.record(req.session_id, "assistant", hermes_response, time.time())

        # Push a snapshot with the fresh memory_recall so the heartbeat
        # panel updates without waiting for a phase transition.
        await _broadcast(
            websocket_clients,
            {
                "type": "cognitive_snapshot",
                **_build_snapshot(_cognitive_loop, recall_blocks).model_dump(),
            },
        )

        return ChatResponse(
            response=hermes_response,
            face_state=face_state,
            personality_prompt=personality_prompt.split("\n")[0] if personality_prompt else None,
        )

    @app.post("/api/memory")
    async def store_memory(req: MemoryStoreRequest):
        from ares.mcp_serve import _store_memory
        return _store_memory(req.content, req.tags, req.source)

    @app.get("/api/memory")
    async def search_memory(query: str, tag: Optional[str] = None, limit: int = 10):
        from ares.mcp_serve import _query_memory
        results = _query_memory(query, tag, limit)
        return {"count": len(results), "results": results}

    @app.get("/api/personality/prompt")
    async def get_personality_prompt():
        return {"prompt": personality.to_system_prompt()}

    @app.get("/api/face/states")
    async def get_face_states():
        return {
            "states": [
                {
                    "name": s.value,
                    "config": {
                        "color": list(get_face_config(s).color),
                        "opacity": get_face_config(s).opacity,
                        "pulse_speed": get_face_config(s).pulse_speed,
                        "pulse_amount": get_face_config(s).pulse_amount,
                        "pupil_offset": list(get_face_config(s).pupil_offset),
                    },
                }
                for s in FaceState
            ]
        }

    # ------------------------------------------------------------------
    # Memory inspector endpoints
    # ------------------------------------------------------------------

    @app.get("/api/memory/episodics")
    async def list_episodics(limit: int = 50):
        """Return recent episodics for the Memory Inspector."""
        return {"items": memory.list_episodics(limit=limit), "count": memory.vectors.count()}

    @app.get("/api/memory/facts")
    async def list_facts(limit: int = 100):
        return {"items": [f.to_dict() for f in memory.list_facts(limit=limit)]}

    @app.post("/api/memory/recall")
    async def recall_memory(body: dict):
        """Run an ad-hoc similarity search."""
        query = (body or {}).get("query", "")
        k = int((body or {}).get("k", 5))
        hits = memory.recall(query, k=k)
        return {"hits": [h.to_dict() for h in hits]}

    @app.delete("/api/memory/episodics/{episodic_id}")
    async def delete_episodic(episodic_id: str):
        memory.delete_episodic(episodic_id)
        return {"deleted": episodic_id}

    # ------------------------------------------------------------------
    # Idle reflexion
    # ------------------------------------------------------------------

    @app.post("/api/idle/run")
    async def run_idle():
        """Trigger a one-shot reflexion pass (consolidate + dedupe + surface)."""
        report = run_idle_pass(memory)
        _last_idle_report.clear()
        _last_idle_report.update(report.to_dict())
        return _last_idle_report

    @app.get("/api/idle/last_report")
    async def last_idle_report():
        return _last_idle_report or {
            "consolidated_sessions": 0,
            "summary_fact_ids": [],
            "duplicates_merged": 0,
            "open_questions": [],
        }

    @app.post("/api/cognitive/start")
    async def start_cognitive_loop(goal: str = "Observe and respond"):
        global _cognitive_loop
        import threading

        if _cognitive_loop is not None and _cognitive_loop._running:
            return {"status": "already_running", "goal": goal}

        loop = create_loop(personality=personality, max_cycles=50)

        # Bridge synchronous phase-change events from the loop thread into
        # the async WebSocket broadcast. The loop runs in a thread; we
        # capture the running event loop here so the observer can schedule
        # the coroutine onto it from the worker thread.
        try:
            main_event_loop = asyncio.get_running_loop()
        except RuntimeError:
            main_event_loop = None

        def _on_phase_change(state):
            # Persist the cycle's reasoning DAG once it's complete (reflect
            # is the last phase per cycle). Stored as episodic metadata so
            # replay can reconstruct the trace.
            if state.phase.name == "REFLECT" and state.branches:
                try:
                    memory.record_episodic(
                        f"[cycle {state.cycle}] " + " → ".join(b.label for b in state.branches),
                        metadata={
                            "kind": "reasoning_trace",
                            "cycle": state.cycle,
                            "dag": [b.to_dict() for b in state.branches],
                        },
                    )
                except Exception as e:
                    logger.warning("DAG persistence failed: %s", e)

            if main_event_loop is None:
                return
            snapshot = _build_snapshot(loop, list(_last_recall))
            payload = {"type": "cognitive_snapshot", **snapshot.model_dump()}
            asyncio.run_coroutine_threadsafe(
                _broadcast(websocket_clients, payload),
                main_event_loop,
            )

        loop.on_phase_change = _on_phase_change
        _cognitive_loop = loop

        def _run_loop():
            try:
                logger.info("Cognitive loop thread starting. Goal: %s", goal)
                result = loop.run(goal=goal)
                logger.info("Cognitive loop complete: %s", result.get("stop_reason", "unknown"))
            except Exception as e:
                logger.error("Cognitive loop error: %s", e)

        thread = threading.Thread(target=_run_loop, daemon=True, name="ares-cognitive-loop")
        thread.start()

        return {"status": "started", "goal": goal, "max_cycles": loop.max_cycles}

    @app.post("/api/cognitive/stop")
    async def stop_cognitive_loop():
        global _cognitive_loop
        if _cognitive_loop is None:
            return {"status": "not_running"}
        _cognitive_loop.stop()
        return {"status": "stopping"}

    @app.get("/api/cognitive/status", response_model=CognitiveSnapshot)
    async def cognitive_status() -> CognitiveSnapshot:
        """Return a CognitiveSnapshot for the current loop (or idle if none).

        The same shape is pushed over the WebSocket as
        `{"type": "cognitive_snapshot", ...}` on every phase transition.
        """
        return _build_snapshot(_cognitive_loop, list(_last_recall))

    # ------------------------------------------------------------------
    # WebSocket
    # ------------------------------------------------------------------

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket):
        await websocket.accept()
        websocket_clients.add(websocket)
        logger.info("WebSocket client connected. Total: %d", len(websocket_clients))
        try:
            while True:
                data = await websocket.receive_text()
                try:
                    cmd = json.loads(data)
                except json.JSONDecodeError:
                    await websocket.send_json({"type": "error", "message": "Invalid JSON"})
                    continue

                action = cmd.get("action", "")
                if action == "set_face_state":
                    state_name = cmd.get("state", "idle")
                    try:
                        new_state = FaceState(state_name)
                        config = get_face_config(new_state)
                        result = {
                            "state": new_state.value,
                            "config": {
                                "color": list(config.color),
                                "opacity": config.opacity,
                                "pulse_speed": config.pulse_speed,
                                "pulse_amount": config.pulse_amount,
                                "pupil_offset": list(config.pupil_offset),
                            },
                        }
                        bus.dispatch(BusMessage(type="face_state", source="websocket", payload=result))
                        await _broadcast(websocket_clients, {"type": "face_state", **result})
                    except ValueError:
                        await websocket.send_json({
                            "type": "error",
                            "message": f"Invalid state: {state_name}. Valid: {[s.value for s in FaceState]}",
                        })

                elif action == "set_personality":
                    layer = cmd.get("layer", "")
                    trait = cmd.get("trait", "")
                    value = cmd.get("value", 0.5)
                    pdata = personality.to_dict()
                    if layer in pdata and trait in pdata[layer]:
                        setattr(getattr(personality, layer), trait, round(float(value), 2))
                        save_personality(personality)
                        await _broadcast(websocket_clients, {
                            "type": "personality_change", "layer": layer, "trait": trait, "value": value,
                        })
                    else:
                        await websocket.send_json({"type": "error", "message": f"Unknown: {layer}.{trait}"})

                elif action == "chat":
                    message = cmd.get("message") or cmd.get("text", "")
                    bus.dispatch(BusMessage(
                        type="chat_message", source="websocket",
                        payload={"message": message, "session_id": cmd.get("session_id")},
                    ))
                    try:
                        async with httpx.AsyncClient(timeout=120.0) as client:
                            resp = await client.post(
                                "http://127.0.0.1:9876/think",
                                json={"text": message},
                            )
                            resp.raise_for_status()
                            data = resp.json()
                            hermes_response = data.get("response", "")
                            face_state = data.get("expression", "speaking")
                    except Exception as e:
                        logger.error("Hermes bridge unreachable (WS chat): %s", e)
                        hermes_response = f"[Bridge error — {e}]"
                        face_state = "thinking"

                    await websocket.send_json({
                        "type": "chat_response", "role": "assistant",
                        "text": hermes_response, "face_state": face_state,
                    })

                elif action == "ping":
                    await websocket.send_json({"type": "pong", "timestamp": time.time()})

                elif action == "get_cognitive_snapshot":
                    snapshot = _build_snapshot(_cognitive_loop, list(_last_recall))
                    await websocket.send_json({
                        "type": "cognitive_snapshot", **snapshot.model_dump(),
                    })

                else:
                    await websocket.send_json({
                        "type": "error", "message": f"Unknown action: {action}",
                        "valid_actions": ["set_face_state", "set_personality", "chat", "ping", "get_cognitive_snapshot"],
                    })

        except WebSocketDisconnect:
            pass
        finally:
            websocket_clients.discard(websocket)
            logger.info("WebSocket client disconnected. Total: %d", len(websocket_clients))

    @app.websocket("/ws/chat")
    async def websocket_alias_endpoint(websocket: WebSocket):
        """Alias endpoint for BrainConnection.swift compatibility."""
        await websocket_endpoint(websocket)

    # Store app state
    app.state.start_time = time.time()
    app.state.websocket_clients = websocket_clients

    return app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _on_face_state(msg: BusMessage):
    """Bus listener that persists face state changes."""
    if msg.type == "face_state" and isinstance(msg.payload, dict):
        _save_face_state({
            "current_state": msg.payload.get("state", "idle"),
            **msg.payload,
        })


def _load_face_state() -> dict:
    from ares.mcp_serve import _load_face_state as _mcp_load
    return _mcp_load()


def _save_face_state(data: dict) -> None:
    from ares.mcp_serve import _save_face_state as _mcp_save
    _mcp_save(data)


async def _broadcast(clients: set, data: dict) -> None:
    """Broadcast a dict to all connected WebSocket clients."""
    disconnected = set()
    for ws in clients:
        try:
            await ws.send_json(data)
        except Exception:
            disconnected.add(ws)
    clients -= disconnected


def _build_snapshot(
    loop: Optional[CognitiveLoop],
    memory_recall: Optional[list[MemoryHitBlock]] = None,
) -> CognitiveSnapshot:
    """Compose a CognitiveSnapshot from a loop instance.

    Accepts None — returns an idle snapshot suitable for the UI heartbeat
    when no loop has been started yet. Lives in the API layer (not in
    `core/cognitive.py`) so the loop has no Pydantic dependency.

    `memory_recall` is passed through to the snapshot when the caller has
    already computed hits (e.g. `/api/chat` recalls before LLM dispatch).
    """
    recall = list(memory_recall) if memory_recall else []
    if loop is None:
        return CognitiveSnapshot(running=False, memory_recall=recall)
    state = loop.state
    elapsed_ms = int(max(0, (time.time() - state.started_at) * 1000))
    branches = [
        ThoughtNode(
            id=b.id,
            parent_ids=list(b.parent_ids),
            label=b.label,
            status=b.status,
            duration_ms=b.duration_ms,
            evidence=list(b.evidence),
        )
        for b in state.branches
    ]
    thought = None
    if branches:
        summary = branches[-1].label if branches[-1].label else None
        thought = ThoughtBlock(summary=summary, depth=len(branches), branches=branches)
    return CognitiveSnapshot(
        running=loop._running,
        loop=LoopBlock(
            cycle=state.cycle,
            phase=state.phase.value,
            urgency=state.urgency.value,
            budget_remaining=state.budget_remaining,
            tokens_used=state.tokens_used,
            elapsed_ms=elapsed_ms,
        ),
        thought=thought,
        memory_recall=recall,
        errors=list(state.errors),
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

app = create_app()

if __name__ == "__main__":
    import uvicorn
    logging.basicConfig(level=logging.INFO)
    logger.info("Starting ARES API server on http://0.0.0.0:7860")
    uvicorn.run(app, host="0.0.0.0", port=7860)
