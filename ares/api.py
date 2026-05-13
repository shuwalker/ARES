"""ARES API Server — FastAPI bridge between Python brain and Swift face.

This is the web layer that lets the SwiftUI app talk to ARES's Python core.
It exposes:

REST endpoints:
    GET  /api/status           — system status
    GET  /api/identity         — who ARES is
    GET  /api/personality       — 4-layer personality profile
    POST /api/personality       — set a personality trait
    GET  /api/face              — current face state
    POST /api/face              — set face state or emotion
    POST /api/chat              — send a message, get a response
    POST /api/memory            — store a fact
    GET  /api/memory            — search memory

WebSocket:
    WS   /ws                    — real-time stream of:
                                   - chat messages
                                   - face state updates
                                   - brain output
                                   - personality changes

The server connects to the ZMQ bus for face state events and dispatches
them to connected WebSocket clients in real time.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from pathlib import Path
from typing import Optional

import httpx

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from ares.core.bus import ARESBus, BusMessage, PortMap, get_bus
from ares.core.cognitive import CognitiveLoop, create_loop
from ares.core.face_state import FaceState, get_face_config, emotion_to_face_state
from ares.core.identity import Identity, DEFAULT_IDENTITY
from ares.core.personality import CharacterProfile, DEFAULT_PROFILE, load_personality, save_personality

logger = logging.getLogger("ares.api")

# Global cognitive loop reference (started on app startup)
_cognitive_loop: Optional[CognitiveLoop] = None

# ---------------------------------------------------------------------------
# Pydantic request/response models
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

def create_app(bus: ARESBus = None, personality: CharacterProfile = None) -> FastAPI:
    """Create the ARES FastAPI application."""
    app = FastAPI(
        title="ARES API",
        version="0.1.0",
        description="Autonomous Reasoning & Execution System — brain API",
    )

    # CORS — allow SwiftUI app to connect from anywhere on the same machine
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:*", "http://127.0.0.1:*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # State
    bus = bus or get_bus()
    personality = personality or load_personality()
    websocket_clients: set = set()

    # -----------------------------------------------------------------------
    # Lifespan: start/stop cognitive loop
    # -----------------------------------------------------------------------
    @app.on_event("startup")
    async def startup():
        global _cognitive_loop
        logger.info("ARES API starting up — initializing cognitive loop")
        # Start bus heartbeat so modules know we're alive
        bus.start_heartbeat(interval_sec=5.0, source="ares_api")
        logger.info("Bus heartbeat started (5s interval)")
        # Initialize face state to idle on startup
        _save_face_state({
            "current_state": "idle",
            "state": "idle",
        })
        logger.info("Face state initialized to idle")

    @app.on_event("shutdown")
    async def shutdown():
        global _cognitive_loop
        logger.info("ARES API shutting down — stopping cognitive loop")
        if _cognitive_loop is not None:
            _cognitive_loop.stop()
        bus.stop()
        logger.info("Bus stopped")

    # -----------------------------------------------------------------------
    # REST endpoints
    # -----------------------------------------------------------------------

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

        # Notify websocket clients
        await _broadcast(websocket_clients, {
            "type": "personality_change",
            "layer": req.layer,
            "trait": req.trait,
            "value": req.value,
        })

        return PersonalityUpdateResponse(
            updated=True, layer=req.layer, trait=req.trait, value=req.value,
        )

    @app.get("/api/face")
    async def get_face_state():
        """Get current face state and all state configurations."""
        return _load_face_state()

    @app.post("/api/face")
    async def set_face_state(req: FaceStateRequest):
        """Set face state or emotion. Triggers face update on all connected clients."""
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

        # Save state
        _save_face_state(result)

        # Dispatch to bus (in-process)
        bus.dispatch(BusMessage(
            type="face_state",
            source="api",
            payload=result,
        ))

        # Broadcast to websocket clients
        await _broadcast(websocket_clients, {
            "type": "face_state",
            **result,
        })

        return result

    @app.post("/api/chat", response_model=ChatResponse)
    async def chat(req: ChatRequest):
        """Send a message to ARES and get a response via Hermes cognition bridge."""
        personality_prompt = personality.to_system_prompt()

        # Dispatch to bus
        bus.dispatch(BusMessage(
            type="chat_message",
            source="api",
            payload={"message": req.message, "session_id": req.session_id},
        ))

        # Forward to Hermes cognition bridge (:9876)
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

        return ChatResponse(
            response=hermes_response,
            face_state=face_state,
            personality_prompt=personality_prompt.split("\n")[0] if personality_prompt else None,
        )

    @app.post("/api/memory")
    async def store_memory(req: MemoryStoreRequest):
        """Store a fact in ARES's memory."""
        from ares.mcp_serve import _store_memory
        result = _store_memory(req.content, req.tags, req.source)
        return result

    @app.get("/api/memory")
    async def search_memory(query: str, tag: Optional[str] = None, limit: int = 10):
        """Search ARES's memory for facts."""
        from ares.mcp_serve import _query_memory
        results = _query_memory(query, tag, limit)
        return {"count": len(results), "results": results}

    @app.get("/api/personality/prompt")
    async def get_personality_prompt():
        """Get the system prompt generated from the current personality profile."""
        return {"prompt": personality.to_system_prompt()}

    @app.get("/api/face/states")
    async def get_face_states():
        """List all valid face states and their configurations."""
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

    @app.post("/api/cognitive/start")
    async def start_cognitive_loop(goal: str = "Observe and respond"):
        """Start the cognitive loop in a background thread.

        The loop runs PERCEIVE→THINK→ACT→REFLECT cycles until it reaches
        a stop condition (budget exhausted, goal completed, or user interrupt).
        """
        global _cognitive_loop
        import threading

        if _cognitive_loop is not None and _cognitive_loop._running:
            return {"status": "already_running", "goal": goal}

        loop = create_loop(personality=personality, max_cycles=50)
        _cognitive_loop = loop

        # Register a bus listener that saves face state changes
        def _on_face_state(msg: BusMessage):
            if msg.type == "face_state" and isinstance(msg.payload, dict):
                _save_face_state({
                    "current_state": msg.payload.get("state", "idle"),
                    **msg.payload,
                })

        bus.on("face_state", _on_face_state)

        # Run the cognitive loop in a background thread
        def _run_loop():
            try:
                logger.info("Cognitive loop thread starting. Goal: %s", goal)
                result = loop.run(goal=goal)
                logger.info("Cognitive loop complete: %s", result.get("stop_reason", "unknown"))
            except Exception as e:
                logger.error("Cognitive loop error: %s", e)

        thread = threading.Thread(target=_run_loop, daemon=True, name="ares-cognitive-loop")
        thread.start()

        return {
            "status": "started",
            "goal": goal,
            "max_cycles": loop.max_cycles,
        }

    @app.post("/api/cognitive/stop")
    async def stop_cognitive_loop():
        """Stop the running cognitive loop."""
        global _cognitive_loop
        if _cognitive_loop is None:
            return {"status": "not_running"}

        _cognitive_loop.stop()
        return {"status": "stopping"}

    @app.get("/api/cognitive/status")
    async def cognitive_status():
        """Get the current cognitive loop status."""
        global _cognitive_loop
        if _cognitive_loop is None:
            return {"running": False, "status": "not_started"}

        return {
            "running": _cognitive_loop._running,
            "cycle": _cognitive_loop.state.cycle,
            "phase": _cognitive_loop.state.phase.value,
            "urgency": _cognitive_loop.state.urgency.value,
            "budget_remaining": _cognitive_loop.state.budget_remaining,
            "face_state": _cognitive_loop.state.face_state.value,
            "errors": _cognitive_loop.state.errors,
        }

    # -----------------------------------------------------------------------
    # WebSocket — real-time streaming
    # -----------------------------------------------------------------------

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket):
        """WebSocket endpoint for real-time streaming.
        
        Sends JSON events:
            {"type": "face_state", "state": "thinking", "config": {...}}
            {"type": "personality_change", "layer": "expression", "trait": "directness", "value": 0.9}
            {"type": "chat_message", "message": "...", "role": "assistant"}
            {"type": "bus_event", ...}
        
        Receives JSON commands:
            {"action": "set_face_state", "state": "thinking"}
            {"action": "set_personality", "layer": "expression", "trait": "directness", "value": 0.9}
            {"action": "chat", "message": "hello"}
        """
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
                            "type": "personality_change",
                            "layer": layer,
                            "trait": trait,
                            "value": value,
                        })
                    else:
                        await websocket.send_json({"type": "error", "message": f"Unknown: {layer}.{trait}"})

                elif action == "chat":
                    message = cmd.get("message") or cmd.get("text", "")
                    bus.dispatch(BusMessage(
                        type="chat_message",
                        source="websocket",
                        payload={"message": message, "session_id": cmd.get("session_id")},
                    ))
                    # Forward to Hermes bridge (:9876)
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
                        "type": "chat_response",
                        "role": "assistant",
                        "text": hermes_response,
                        "face_state": face_state,
                    })

                elif action == "ping":
                    await websocket.send_json({"type": "pong", "timestamp": time.time()})

                else:
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Unknown action: {action}",
                        "valid_actions": ["set_face_state", "set_personality", "chat", "ping"],
                    })

        except WebSocketDisconnect:
            pass
        finally:
            websocket_clients.discard(websocket)
            logger.info("WebSocket client disconnected. Total: %d", len(websocket_clients))

    @app.websocket("/ws/chat")
    async def websocket_alias_endpoint(websocket: WebSocket):
        """Alias endpoint for BrainConnection.swift and any docs referencing /ws/chat."""
        await websocket_endpoint(websocket)

    return app


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_face_state() -> dict:
    """Load current face state."""
    from ares.mcp_serve import _load_face_state as _mcp_load
    return _mcp_load()


def _save_face_state(data: dict) -> None:
    """Save face state."""
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


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

app = create_app()

if __name__ == "__main__":
    import uvicorn
    logging.basicConfig(level=logging.INFO)
    logger.info("Starting ARES API server on http://0.0.0.0:7860")
    uvicorn.run(app, host="0.0.0.0", port=7860)