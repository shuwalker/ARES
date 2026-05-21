"""ARES API Server — FastAPI bridge between Python brain and Swift face.

This is the web layer that lets the SwiftUI app talk to ARES's Python core.
Route handlers live here; models are in ares.models.api, service lifecycle
is in ares.runtime.service_manager.

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

import json
import logging
import os
import socket
import time
from contextlib import asynccontextmanager
from typing import Any, Optional


from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from ares.core.bus import ARESBus, BusMessage, get_bus
from ares.core.face_state import FaceState, get_face_config, emotion_to_face_state
from ares.core.identity import DEFAULT_IDENTITY
from ares.core.personality import CharacterProfile, load_personality, save_personality
from ares.core.memory_store import MemoryStore, default_memory_store
from ares.models.api import (
    ChatRequest,
    ChatResponse,
    FaceConfigBlock,
    FaceStateEntry,
    FaceStateRequest,
    FaceStateResponse,
    FaceStatesResponse,
    IdentityResponse,
    MemorySearchResponse,
    MemoryStoreRequest,
    MemoryStoreResponse,
    PersonalityPromptResponse,
    PersonalityUpdateRequest,
    PersonalityUpdateResponse,
    ServiceHealth,
    ServicesResponse,
    StatusResponse,
)
from ares.models.cognitive import CognitiveSnapshot, MemoryHitBlock
from ares.runtime.service_manager import SERVICES, _get_api_client
from ares.runtime.session_store import SessionStore

logger = logging.getLogger("ares.api")


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

        # ── Startup ──────────────────────────────────────────────────
        logger.info("ARES API starting — initializing all services")
        bus.start_heartbeat(interval_sec=5.0, source="ares_api")

        # Start all MCP servers + bridge
        for svc in SERVICES:
            await svc.start()

        # Initialize face state
        _save_face_state({"current_state": "idle", "state": "idle"})

        # Connect to cognition bus
        bus.on("face_state", _on_face_state)

        logger.info("ARES API ready — all services launched")
        yield

        # ── Shutdown ─────────────────────────────────────────────────
        logger.info("ARES API shutting down — stopping all services")

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

    # Plugin routers
    from ares.plugins.lifetrack.api import router as lifetrack_router
    app.include_router(lifetrack_router)

    # ------------------------------------------------------------------
    # REST endpoints
    # ------------------------------------------------------------------

    @app.get("/api/status", response_model=StatusResponse)
    async def get_status() -> StatusResponse:
        """Get ARES system status."""
        identity = DEFAULT_IDENTITY
        face_data = _load_face_state()
        bus_status = bus.status()
        return StatusResponse(
            name=identity.name,
            version="0.1.0",
            face_state=face_data.get("current_state", "unknown"),
            bus=bus_status,
            websocket_clients=len(websocket_clients),
            uptime=time.time(),
        )

    @app.get("/api/stack")
    async def get_stack():
        """Get the ARES 2 agent-stack rebuild manifest."""
        from ares.runtime.agent_stack import stack_status

        return stack_status()

    @app.get("/api/services", response_model=ServicesResponse)
    async def get_services() -> ServicesResponse:
        """Get health status of all ARES services."""
        # Check external Mac MCP first
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

        return ServicesResponse(
            status="ok",
            timestamp=time.time(),
            total=len(all_services),
            healthy=sum(1 for s in all_services if s.get("reachable")),
            services=[ServiceHealth.model_validate(s) for s in all_services],
        )

    @app.get("/api/identity", response_model=IdentityResponse)
    async def get_identity() -> IdentityResponse:
        """Get ARES's identity — name, role, voice, self-model."""
        identity = DEFAULT_IDENTITY
        return IdentityResponse(
            name=identity.name,
            role=identity.role,
            voice=identity.voice,
            self_model=identity.self_model,
        )

    @app.get("/api/personality")
    async def get_personality() -> dict[str, Any]:
        return personality.to_dict()

    @app.post("/api/personality", response_model=PersonalityUpdateResponse)
    async def set_personality(req: PersonalityUpdateRequest):
        """Set a personality trait (0.0-1.0)."""
        pdata = personality.to_dict()
        if req.layer not in pdata:
            raise HTTPException(400, f"Unknown layer: {req.layer}. Must be one of: {list(pdata.keys())}")
        if req.trait not in pdata[req.layer]:
            raise HTTPException(
                400, f"Unknown trait: {req.trait} in {req.layer}. Available: {list(pdata[req.layer].keys())}"
            )

        setattr(getattr(personality, req.layer), req.trait, round(req.value, 2))
        save_personality(personality)

        await _broadcast(
            websocket_clients,
            {
                "type": "personality_change",
                "layer": req.layer,
                "trait": req.trait,
                "value": req.value,
            },
        )

        return PersonalityUpdateResponse(updated=True, layer=req.layer, trait=req.trait, value=req.value)

    @app.get("/api/face", response_model=FaceStateResponse)
    async def get_face_state() -> FaceStateResponse:
        """Get current face state and all state configurations."""
        return FaceStateResponse.model_validate(_load_face_state())

    @app.post("/api/face", response_model=FaceStateResponse)
    async def set_face_state(req: FaceStateRequest) -> FaceStateResponse:
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
            return FaceStateResponse.model_validate(_load_face_state())

        _save_face_state(result)
        bus.dispatch(BusMessage(type="face_state", source="api", payload=result))
        await _broadcast(websocket_clients, {"type": "face_state", **result})
        return FaceStateResponse.model_validate(result)

    @app.post("/api/chat", response_model=ChatResponse)
    async def chat(req: ChatRequest):
        """Send a message to ARES and get a response via Hermes cognition bridge."""
        personality_prompt = personality.to_system_prompt()

        # Pull relevant episodic memory
        hits = memory.recall(req.message, k=5)
        recall_blocks = [MemoryHitBlock(id=h.id, score=h.score, text=h.text, kind=h.kind) for h in hits]
        _last_recall.clear()
        _last_recall.extend(recall_blocks)

        if req.session_id:
            sessions.record(req.session_id, "user", req.message, time.time())

        bus.dispatch(
            BusMessage(
                type="chat_message",
                source="api",
                payload={"message": req.message, "session_id": req.session_id},
            )
        )

        # Use shared httpx client instead of per-request
        try:
            client = _get_api_client()
            resp = await client.post(
                "http://127.0.0.1:9876/think",
                json={"text": req.message},
                timeout=120.0,
            )
            resp.raise_for_status()
            data = resp.json()
            hermes_response = data.get("response", "")
            face_state = data.get("expression", "speaking")
        except Exception as e:
            logger.error("Hermes bridge unreachable: %s", e)
            hermes_response = f"[ARES bridge error — {e}]"
            face_state = "thinking"

        # Persist the exchange
        try:
            memory.record_episodic(
                f"USER: {req.message}\nARES: {hermes_response}",
                metadata={"session_id": req.session_id, "kind": "exchange"},
            )
        except Exception as e:
            logger.warning("Episodic write failed: %s", e)
        if req.session_id:
            sessions.record(req.session_id, "assistant", hermes_response, time.time())

        await _broadcast(
            websocket_clients,
            {
                "type": "cognitive_snapshot",
                **_build_snapshot(recall_blocks).model_dump(),
            },
        )

        return ChatResponse(
            response=hermes_response,
            face_state=face_state,
            personality_prompt=personality_prompt.split("\n")[0] if personality_prompt else None,
        )

    @app.post("/api/memory", response_model=MemoryStoreResponse)
    async def store_memory(req: MemoryStoreRequest) -> MemoryStoreResponse:
        from ares.runtime.mcp_serve import _store_memory

        return MemoryStoreResponse.model_validate(_store_memory(req.content, req.tags, req.source))

    @app.get("/api/memory", response_model=MemorySearchResponse)
    async def search_memory(query: str, tag: Optional[str] = None, limit: int = 10) -> MemorySearchResponse:
        from ares.runtime.mcp_serve import _query_memory

        results = _query_memory(query, tag, limit)
        return MemorySearchResponse(count=len(results), results=results)

    @app.get("/api/personality/prompt", response_model=PersonalityPromptResponse)
    async def get_personality_prompt() -> PersonalityPromptResponse:
        return PersonalityPromptResponse(prompt=personality.to_system_prompt())

    @app.get("/api/face/states", response_model=FaceStatesResponse)
    async def get_face_states() -> FaceStatesResponse:
        return FaceStatesResponse(
            states=[
                FaceStateEntry(
                    name=s.value,
                    config=FaceConfigBlock(
                        color=list(get_face_config(s).color),
                        opacity=get_face_config(s).opacity,
                        pulse_speed=get_face_config(s).pulse_speed,
                        pulse_amount=get_face_config(s).pulse_amount,
                        pupil_offset=list(get_face_config(s).pupil_offset),
                    ),
                )
                for s in FaceState
            ]
        )

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
    # Idle reflexion & cognitive loop stubs
    # ------------------------------------------------------------------

    @app.post("/api/idle/run")
    async def run_idle():
        """Trigger a one-shot reflexion pass. Stub — not yet reimplemented."""
        return {"status": "disabled", "message": "Idle reflexion not yet reimplemented after architecture cleanup."}

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
        """Start the cognitive loop. Stub — will delegate to AgentInterface."""
        return {
            "status": "disabled",
            "message": "Cognitive loop not yet reimplemented. Use /api/chat for direct Hermes queries.",
        }

    @app.post("/api/cognitive/stop")
    async def stop_cognitive_loop():
        return {"status": "not_running"}

    @app.get("/api/cognitive/status", response_model=CognitiveSnapshot)
    async def cognitive_status() -> CognitiveSnapshot:
        """Return idle cognitive snapshot."""
        return CognitiveSnapshot(running=False, memory_recall=list(_last_recall))

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
                        await websocket.send_json(
                            {
                                "type": "error",
                                "message": f"Invalid state: {state_name}. Valid: {[s.value for s in FaceState]}",
                            }
                        )

                elif action == "set_personality":
                    layer = cmd.get("layer", "")
                    trait = cmd.get("trait", "")
                    value = cmd.get("value", 0.5)
                    pdata = personality.to_dict()
                    if layer in pdata and trait in pdata[layer]:
                        setattr(getattr(personality, layer), trait, round(float(value), 2))
                        save_personality(personality)
                        await _broadcast(
                            websocket_clients,
                            {
                                "type": "personality_change",
                                "layer": layer,
                                "trait": trait,
                                "value": value,
                            },
                        )
                    else:
                        await websocket.send_json({"type": "error", "message": f"Unknown: {layer}.{trait}"})

                elif action == "chat":
                    message = cmd.get("message") or cmd.get("text", "")
                    bus.dispatch(
                        BusMessage(
                            type="chat_message",
                            source="websocket",
                            payload={"message": message, "session_id": cmd.get("session_id")},
                        )
                    )
                    # Use shared httpx client
                    try:
                        client = _get_api_client()
                        resp = await client.post(
                            "http://127.0.0.1:9876/think",
                            json={"text": message},
                            timeout=120.0,
                        )
                        resp.raise_for_status()
                        data = resp.json()
                        hermes_response = data.get("response", "")
                        face_state = data.get("expression", "speaking")
                    except Exception as e:
                        logger.error("Hermes bridge unreachable (WS chat): %s", e)
                        hermes_response = f"[Bridge error — {e}]"
                        face_state = "thinking"

                    await websocket.send_json(
                        {
                            "type": "chat_response",
                            "role": "assistant",
                            "text": hermes_response,
                            "face_state": face_state,
                        }
                    )

                elif action == "ping":
                    await websocket.send_json({"type": "pong", "timestamp": time.time()})

                elif action == "get_cognitive_snapshot":
                    snapshot = _build_snapshot(list(_last_recall))
                    await websocket.send_json(
                        {
                            "type": "cognitive_snapshot",
                            **snapshot.model_dump(),
                        }
                    )

                else:
                    await websocket.send_json(
                        {
                            "type": "error",
                            "message": f"Unknown action: {action}",
                            "valid_actions": [
                                "set_face_state",
                                "set_personality",
                                "chat",
                                "ping",
                                "get_cognitive_snapshot",
                            ],
                        }
                    )

        except WebSocketDisconnect:
            pass
        finally:
            websocket_clients.discard(websocket)
            logger.info("WebSocket client disconnected. Total: %d", len(websocket_clients))

    @app.websocket("/ws/chat")
    async def websocket_alias_endpoint(websocket: WebSocket):
        """Alias endpoint for BrainConnection.swift compatibility."""
        await websocket_endpoint(websocket)

    # ------------------------------------------------------------------
    # Collaboration Hub — Claude + Hermes bidirectional coordination
    # ------------------------------------------------------------------

    from ares.runtime.collaboration import get_hub, AgentStatus

    hub = get_hub()
    collab_clients: set = set()

    @app.post("/api/collaboration/session")
    async def create_collab_session(body: dict):
        """Create a new collaboration session."""
        session_id = body.get("session_id", "session_" + str(int(time.time())))
        goal = body.get("goal", "Collaborative work")
        session = hub.create_session(session_id, goal)
        await _broadcast_collab({"type": "session_created", "session": session.to_dict()})
        return session.to_dict()

    @app.get("/api/collaboration/session")
    async def get_collab_session(session_id: Optional[str] = None):
        """Get collaboration session state."""
        session = hub.get_session(session_id)
        if not session:
            raise HTTPException(404, "Session not found")
        return session.to_dict()

    @app.post("/api/collaboration/request")
    async def request_agent_help(body: dict):
        """Request help from another agent."""
        session_id = body.get("session_id")
        from_agent = body.get("from_agent")
        to_agent = body.get("to_agent")
        task = body.get("task")
        context = body.get("context", {})

        session = hub.get_session(session_id)
        if not session:
            raise HTTPException(404, "Session not found")

        task_id = session.queue_task(from_agent, to_agent, task, context)
        session.update_agent_status(from_agent, AgentStatus.WORKING, task)

        await _broadcast_collab({
            "type": "task_request",
            "from_agent": from_agent,
            "to_agent": to_agent,
            "task_id": task_id,
            "task": task,
            "context": context,
            "session": session.to_dict()
        })

        return {"task_id": task_id, "status": "queued"}

    @app.post("/api/collaboration/complete")
    async def complete_agent_task(body: dict):
        """Report task completion."""
        session_id = body.get("session_id")
        task_id = body.get("task_id")
        agent_name = body.get("agent")
        result = body.get("result")

        session = hub.get_session(session_id)
        if not session:
            raise HTTPException(404, "Session not found")

        session.complete_task(task_id, result)
        session.update_agent_status(agent_name, AgentStatus.IDLE)

        await _broadcast_collab({
            "type": "task_completed",
            "task_id": task_id,
            "agent": agent_name,
            "result": result,
            "session": session.to_dict()
        })

        return {"status": "completed"}

    @app.post("/api/collaboration/status")
    async def update_agent_status(body: dict):
        """Update agent status."""
        session_id = body.get("session_id")
        agent_name = body.get("agent")
        status = body.get("status")
        task = body.get("task")

        session = hub.get_session(session_id)
        if not session:
            raise HTTPException(404, "Session not found")

        session.update_agent_status(agent_name, AgentStatus(status), task)

        await _broadcast_collab({
            "type": "status_update",
            "agent": agent_name,
            "status": status,
            "session": session.to_dict()
        })

        return {"status": "updated"}

    @app.websocket("/ws/collaborate")
    async def websocket_collaborate(websocket: WebSocket):
        """WebSocket endpoint for real-time agent collaboration."""
        await websocket.accept()
        collab_clients.add(websocket)
        logger.info("Collaboration client connected")

        try:
            while True:
                data = await websocket.receive_json()
                msg_type = data.get("type")
                session_id = data.get("session_id")
                agent = data.get("agent")

                session = hub.get_session(session_id)
                if not session:
                    await websocket.send_json({"error": "Session not found"})
                    continue

                if msg_type == "heartbeat":
                    session.update_agent_status(agent, AgentStatus.WORKING)
                    await websocket.send_json({"type": "heartbeat_ack", "timestamp": time.time()})

                elif msg_type == "request_task":
                    # Agent is requesting work
                    task = data.get("task")
                    to_agent = data.get("to_agent")
                    context = data.get("context", {})
                    task_id = session.queue_task(agent, to_agent, task, context)
                    await _broadcast_collab({
                        "type": "task_request",
                        "task_id": task_id,
                        "from_agent": agent,
                        "to_agent": to_agent,
                        "task": task,
                        "session": session.to_dict()
                    })

                elif msg_type == "task_completed":
                    # Agent completed a task
                    task_id = data.get("task_id")
                    result = data.get("result")
                    session.complete_task(task_id, result)
                    session.update_agent_status(agent, AgentStatus.IDLE)
                    await _broadcast_collab({
                        "type": "task_completed",
                        "task_id": task_id,
                        "agent": agent,
                        "result": result,
                        "session": session.to_dict()
                    })

        except WebSocketDisconnect:
            collab_clients.discard(websocket)
            logger.info(f"Collaboration client disconnected")

    async def _broadcast_collab(message: dict) -> None:
        """Broadcast collaboration message to all connected agents."""
        disconnected = set()
        for ws in collab_clients:
            try:
                await ws.send_json(message)
            except Exception:
                disconnected.add(ws)
        collab_clients -= disconnected

    # Store app state
    app.state.start_time = time.time()
    app.state.websocket_clients = websocket_clients
    app.state.collab_clients = collab_clients

    return app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _on_face_state(msg: BusMessage):
    """Bus listener that persists face state changes."""
    if msg.type == "face_state" and isinstance(msg.payload, dict):
        _save_face_state(
            {
                "current_state": msg.payload.get("state", "idle"),
                **msg.payload,
            }
        )


def _load_face_state() -> dict:
    from ares.runtime.mcp_serve import _load_face_state as _mcp_load

    return _mcp_load()


def _save_face_state(data: dict) -> None:
    from ares.runtime.mcp_serve import _save_face_state as _mcp_save

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
    memory_recall: Optional[list[MemoryHitBlock]] = None,
) -> CognitiveSnapshot:
    """Compose an idle CognitiveSnapshot."""
    recall = list(memory_recall) if memory_recall else []
    return CognitiveSnapshot(running=False, memory_recall=recall)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

app = create_app()

if __name__ == "__main__":
    import uvicorn

    logging.basicConfig(level=logging.INFO)
    logger.info("Starting ARES API server on http://0.0.0.0:7860")
    uvicorn.run(app, host="0.0.0.0", port=7860)
