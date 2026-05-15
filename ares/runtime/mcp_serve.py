"""ARES MCP Server — expose ARES cognitive tools to MCP clients.

Adds ARES-specific tools on top of Hermes' existing messaging MCP server.
Any MCP client (Claude Code, Cursor, Codex, etc.) can call these tools
to interact with ARES's identity, personality, face state, memory, and
brain transport systems.

Usage:
    ares mcp serve
    ares mcp serve --verbose

MCP client config (e.g. claude_desktop_config.json):
    {
        "mcpServers": {
            "ares": {
                "command": "python",
                "args": ["-m", "ares.mcp_serve"]
            }
        }
    }
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
import sys
import time
from pathlib import Path
from typing import Optional

logger = logging.getLogger("ares.mcp_serve")

# ---------------------------------------------------------------------------
# Lazy MCP SDK import
# ---------------------------------------------------------------------------

_MCP_SERVER_AVAILABLE = False
try:
    from mcp.server.fastmcp import FastMCP

    _MCP_SERVER_AVAILABLE = True
except ImportError:
    FastMCP = None


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------


def _get_ares_home() -> Path:
    return Path(os.environ.get("ARES_HOME", Path.home() / ".ares"))


def _get_hermes_home() -> Path:
    return Path(os.environ.get("HERMES_HOME", _get_ares_home() / ".hermes"))


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------


def _load_identity() -> dict:
    """Load ARES identity from JSON or defaults."""
    identity_path = _get_ares_home() / "identity.json"
    if identity_path.exists():
        try:
            return json.loads(identity_path.read_text())
        except Exception:
            pass
    try:
        from ares.core.identity import DEFAULT_IDENTITY

        return {
            "name": DEFAULT_IDENTITY.name,
            "role": DEFAULT_IDENTITY.role,
            "voice": DEFAULT_IDENTITY.voice,
            "self_model": DEFAULT_IDENTITY.self_model,
        }
    except ImportError:
        return {
            "name": "ARES",
            "role": "AI co-founder of Jenkins Robotics",
            "voice": "Direct and technical. No filler, no flattery, no padding.",
            "self_model": "Distributed entity across Mac Studio + RackPC.",
        }


def _load_personality() -> dict:
    """Load 4-layer personality from JSON or defaults."""
    personality_path = _get_ares_home() / "personality.json"
    if personality_path.exists():
        try:
            return json.loads(personality_path.read_text())
        except Exception:
            pass
    try:
        from ares.core.personality import DEFAULT_PROFILE

        return DEFAULT_PROFILE.to_dict()
    except ImportError:
        return {
            "hexaco": {
                "openness": 0.85,
                "conscientiousness": 0.78,
                "extraversion": 0.55,
                "agreeableness": 0.62,
                "neuroticism": 0.30,
                "honesty_humility": 0.82,
            },
            "special": {
                "strength": 0.65,
                "perception": 0.90,
                "endurance": 0.70,
                "charisma": 0.55,
                "intelligence": 0.92,
                "agility": 0.75,
                "luck": 0.60,
            },
            "expression": {
                "sarcasm": 0.40,
                "warmth": 0.55,
                "verbosity": 0.35,
                "formality": 0.45,
                "directness": 0.90,
                "humor": 0.30,
                "empathy": 0.65,
                "aggression": 0.25,
            },
            "domains": {
                "science": 0.85,
                "philosophy": 0.50,
                "combat": 0.15,
                "art": 0.30,
                "politics": 0.10,
                "technology": 0.95,
                "nature": 0.25,
                "psychology": 0.60,
            },
        }


def _load_face_state() -> dict:
    """Load current face state from JSON or defaults."""
    state_path = _get_ares_home() / "face_state.json"
    if state_path.exists():
        try:
            return json.loads(state_path.read_text())
        except Exception:
            pass
    try:
        from ares.core.face_state import FaceState, STATE_CONFIGS

        return {
            "current_state": "idle",
            "states": [s.value for s in FaceState],
            "config": {
                state.value: {
                    "color": list(cfg.color),
                    "opacity": cfg.opacity,
                    "pulse_speed": cfg.pulse_speed,
                    "pulse_amount": cfg.pulse_amount,
                    "pupil_offset": list(cfg.pupil_offset),
                }
                for state, cfg in STATE_CONFIGS.items()
            },
        }
    except ImportError:
        return {"current_state": "idle", "states": [], "config": {}}


def _save_face_state(data: dict) -> None:
    """Persist face state to JSON."""
    state_path = _get_ares_home() / "face_state.json"
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(data, indent=2))


def _publish_face_state(state_value: str, config: dict) -> None:
    """Try to publish face state update to ZMQ bus (non-blocking, best-effort)."""
    try:
        import zmq

        ctx = zmq.Context.instance()
        sock = ctx.socket(zmq.PUB)
        sock.connect("tcp://localhost:5572")
        sock.send_json({"type": "face_state", "state": state_value, **config})
        sock.close()
    except Exception:
        pass  # ZMQ not running — that's fine


def _query_memory(query: str, tag: Optional[str] = None, limit: int = 10) -> list[dict]:
    """Query ARES memory (SQLite)."""
    ares_db = _get_ares_home() / "memory.db"
    if not ares_db.exists():
        return []
    try:
        conn = sqlite3.connect(str(ares_db))
        conn.row_factory = sqlite3.Row
        tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        if "facts" not in tables:
            conn.close()
            return []
        conditions = []
        params: list = []
        if query:
            conditions.append("content LIKE ?")
            params.append(f"%{query}%")
        if tag:
            conditions.append("tags LIKE ?")
            params.append(f"%{tag}%")
        where = " AND ".join(conditions) if conditions else "1=1"
        rows = conn.execute(
            f"SELECT id, content, tags, source, learned_at FROM facts "
            f"WHERE {where} ORDER BY learned_at DESC LIMIT ?",
            params + [limit],
        ).fetchall()
        conn.close()
        return [dict(r) for r in rows]
    except Exception as e:
        logger.debug("Memory query failed: %s", e)
        return []


def _store_memory(content: str, tags: Optional[str] = None, source: str = "mcp") -> dict:
    """Store a fact in ARES memory."""
    tag_list = [t.strip() for t in tags.split(",")] if tags else []
    ares_db = _get_ares_home() / "memory.db"
    ares_db.parent.mkdir(parents=True, exist_ok=True)
    try:
        from ares.core.memory import Memory

        mem = Memory(ares_db)
        mem.open()
        fact_id = mem.remember(content, tag_list, source)
        mem.close()
        return {"stored": True, "id": fact_id, "content": content, "tags": tag_list}
    except ImportError:
        conn = sqlite3.connect(str(ares_db))
        conn.execute(
            "CREATE TABLE IF NOT EXISTS facts "
            "(id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, "
            "tags TEXT NOT NULL DEFAULT '[]', source TEXT NOT NULL DEFAULT 'mcp', "
            "learned_at REAL NOT NULL)"
        )
        conn.execute(
            "INSERT INTO facts (content, tags, source, learned_at) VALUES (?, ?, ?, ?)",
            (content, json.dumps(tag_list), source, time.time()),
        )
        conn.commit()
        fact_id = str(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
        conn.close()
        return {"stored": True, "id": fact_id, "content": content, "tags": tag_list}


# ---------------------------------------------------------------------------
# Create MCP Server
# ---------------------------------------------------------------------------


def create_mcp_server() -> "FastMCP":
    """Create and return the ARES MCP server with all tools registered."""
    if not _MCP_SERVER_AVAILABLE:
        raise ImportError(
            "MCP server requires the 'mcp' package. " f"Install with: {sys.executable} -m pip install 'mcp'"
        )

    mcp = FastMCP(
        "ares",
        instructions=(
            "ARES (Autonomous Reasoning Execution System) — cognitive layer "
            "tools for identity, personality, face state, memory, and system "
            "status. Use these tools to query and modify ARES's self-model, "
            "emotional state, and persistent memory."
        ),
    )

    # -- ares_identity -----------------------------------------------------

    @mcp.tool()
    def ares_identity() -> str:
        """Get ARES's current identity — name, role, voice, and self-model."""
        identity = _load_identity()
        return json.dumps(identity, indent=2)

    # -- ares_personality --------------------------------------------------

    @mcp.tool()
    def ares_personality() -> str:
        """Get ARES's 4-layer personality profile.

        Returns HEXACO personality, SPECIAL capabilities, Expression style,
        and Domain expertise weights (all 0.0-1.0).
        """
        personality = _load_personality()
        return json.dumps(personality, indent=2)

    # -- ares_set_personality -----------------------------------------------

    @mcp.tool()
    def ares_set_personality(layer: str, trait: str, value: float) -> str:
        """Set a personality trait value (0.0-1.0).

        Args:
            layer: One of "hexaco", "special", "expression", "domains"
            trait: The trait name within the layer (e.g. "openness", "directness")
            value: New value (0.0 to 1.0, clamped to range)
        """
        personality = _load_personality()
        if layer not in personality:
            return json.dumps({"error": f"Unknown layer: {layer}. " f"Must be one of: {', '.join(personality.keys())}"})
        if trait not in personality[layer]:
            return json.dumps(
                {
                    "error": f"Unknown trait: {trait} in layer {layer}. "
                    f"Available: {', '.join(personality[layer].keys())}"
                }
            )
        personality[layer][trait] = round(max(0.0, min(1.0, value)), 2)
        personality_path = _get_ares_home() / "personality.json"
        personality_path.parent.mkdir(parents=True, exist_ok=True)
        personality_path.write_text(json.dumps(personality, indent=2))
        return json.dumps(
            {
                "updated": True,
                "layer": layer,
                "trait": trait,
                "value": personality[layer][trait],
            },
            indent=2,
        )

    # -- ares_set_face_state -----------------------------------------------

    @mcp.tool()
    def ares_set_face_state(
        state: Optional[str] = None,
        emotion: Optional[str] = None,
    ) -> str:
        """Set ARES's face state or emotion.

        Valid states: idle, awakened, listening, thinking, speaking, sleeping
        Valid emotions: happy, sad, thinking, surprised, neutral, curious, etc.

        Args:
            state: Set face to this named state
            emotion: Map an emotion name to a face state
        """
        from ares.core.face_state import FaceState, get_face_config, emotion_to_face_state

        if state is not None:
            try:
                new_state = FaceState(state)
            except ValueError:
                return json.dumps({"error": f"Invalid state: {state}. " f"Valid: {[s.value for s in FaceState]}"})
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
            _save_face_state(result)
            _publish_face_state(new_state.value, result["config"])
            return json.dumps(result, indent=2)

        if emotion is not None:
            new_state = emotion_to_face_state(emotion)
            config = get_face_config(new_state)
            result = {
                "emotion": emotion,
                "state": new_state.value,
                "config": {
                    "color": list(config.color),
                    "opacity": config.opacity,
                    "pulse_speed": config.pulse_speed,
                    "pulse_amount": config.pulse_amount,
                    "pupil_offset": list(config.pupil_offset),
                },
            }
            _save_face_state(result)
            _publish_face_state(new_state.value, result["config"])
            return json.dumps(result, indent=2)

        # No args — return current state
        current = _load_face_state()
        return json.dumps(current, indent=2)

    # -- ares_get_face_state ------------------------------------------------

    @mcp.tool()
    def ares_get_face_state() -> str:
        """Get ARES's current face state and all state configurations."""
        current = _load_face_state()
        return json.dumps(current, indent=2)

    # -- ares_memory_query -------------------------------------------------

    @mcp.tool()
    def ares_memory_query(
        query: str,
        tag: Optional[str] = None,
        limit: int = 10,
    ) -> str:
        """Search ARES's persistent memory for facts.

        Args:
            query: Text to search for (substring match)
            tag: Optional tag to filter by
            limit: Maximum results (default 10, max 100)
        """
        limit = max(1, min(100, int(limit)))
        results = _query_memory(query, tag, limit)
        if not results:
            return json.dumps(
                {
                    "count": 0,
                    "results": [],
                    "note": "No matching facts. Memory may be empty or query too specific.",
                },
                indent=2,
            )
        return json.dumps({"count": len(results), "results": results}, indent=2)

    # -- ares_memory_remember -----------------------------------------------

    @mcp.tool()
    def ares_memory_remember(
        content: str,
        tags: Optional[str] = None,
        source: str = "mcp",
    ) -> str:
        """Store a fact in ARES's persistent memory.

        Args:
            content: The fact to remember
            tags: Comma-separated tags for categorization (e.g. "robotics,jp01")
            source: Source identifier (default: "mcp")
        """
        result = _store_memory(content, tags, source)
        return json.dumps(result, indent=2)

    # -- ares_status -------------------------------------------------------

    @mcp.tool()
    def ares_status() -> str:
        """Get ARES system status — brain transport, Hermes, face state, personality."""
        identity = _load_identity()
        face = _load_face_state()

        # Check Hermes availability
        hermes_status = "unknown"
        try:
            hermes_bin = Path.home() / ".hermes" / "hermes-agent" / "venv" / "bin" / "hermes"
            ares_hermes = _get_ares_home() / "hermes-agent" / "venv" / "bin" / "hermes"
            if ares_hermes.exists():
                hermes_status = "available (ares-managed)"
            elif hermes_bin.exists():
                hermes_status = "available (legacy)"
            else:
                hermes_status = "not found"
        except Exception:
            hermes_status = "check_failed"

        # Brain transport status
        ares_hermes = _get_hermes_home()
        legacy_hermes = Path.home() / ".hermes"
        transport = {
            "migrated": ares_hermes.exists(),
            "ares_home": str(_get_ares_home()),
            "hermes_home": str(ares_hermes),
            "legacy_home": str(legacy_hermes),
            "legacy_exists": legacy_hermes.exists(),
        }

        return json.dumps(
            {
                "name": identity.get("name", "ARES"),
                "brain_transport": transport,
                "hermes": hermes_status,
                "face_state": face.get("current_state", "unknown"),
                "ares_home": str(_get_ares_home()),
                "hermes_home": str(_get_hermes_home()),
            },
            indent=2,
        )

    # -- ares_tools --------------------------------------------------------

    @mcp.tool()
    def ares_tools() -> str:
        """List all ARES MCP tools with descriptions."""
        return json.dumps(
            {
                "tools": [
                    {"name": "ares_identity", "description": "Get identity — name, role, voice, self-model"},
                    {"name": "ares_personality", "description": "Get 4-layer personality profile"},
                    {
                        "name": "ares_set_personality",
                        "description": "Set a personality trait value",
                        "params": ["layer", "trait", "value"],
                    },
                    {
                        "name": "ares_set_face_state",
                        "description": "Set face state or emotion",
                        "params": ["state", "emotion"],
                    },
                    {"name": "ares_get_face_state", "description": "Get current face state and all configs"},
                    {
                        "name": "ares_memory_query",
                        "description": "Search persistent memory for facts",
                        "params": ["query", "tag?", "limit?"],
                    },
                    {
                        "name": "ares_memory_remember",
                        "description": "Store a fact in persistent memory",
                        "params": ["content", "tags?", "source?"],
                    },
                    {"name": "ares_status", "description": "Get system status"},
                ],
            },
            indent=2,
        )

    return mcp


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def run_mcp_server(verbose: bool = False) -> None:
    """Start the ARES MCP server on stdio."""
    if not _MCP_SERVER_AVAILABLE:
        print(
            "Error: MCP server requires the 'mcp' package.\n" f"Install with: {sys.executable} -m pip install 'mcp'",
            file=sys.stderr,
        )
        sys.exit(1)

    if verbose:
        logging.basicConfig(level=logging.DEBUG, stream=sys.stderr)
    else:
        logging.basicConfig(level=logging.WARNING, stream=sys.stderr)

    server = create_mcp_server()

    import asyncio

    async def _run():
        await server.run_stdio_async()

    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="ARES MCP Server")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    args = parser.parse_args()
    run_mcp_server(verbose=args.verbose)
