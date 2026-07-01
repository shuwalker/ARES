"""JROS persona injection — loads YAML personas and builds system prompt prefix.

Reads persona YAMLs from JROS's personas/ directory (or a configured path),
parses the persona/v1 schema, and renders a system prompt section that gets
injected into the Hermes agent's ephemeral_system_prompt.

Zero coupling to JROS runtime — this only reads YAML files. The JROS daemon
doesn't need to be running. The persona is pure prompt text.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Optional

import yaml

logger = logging.getLogger(__name__)

# Default: JROS personas live here on Matthew's machine.
_DEFAULT_PERSONA_DIR = os.path.expanduser("~/GitHub/JROS/jaeger_os/personas")

# Env override for portability.
_PERSONA_DIR_ENV = "ARES_PERSONA_DIR"


def _persona_dir() -> Path:
    """Return the persona directory, checking env override first."""
    raw = os.getenv(_PERSONA_DIR_ENV, _DEFAULT_PERSONA_DIR)
    return Path(raw).expanduser()


def list_personas() -> list[dict[str, str]]:
    """Return all available personas as [{id, name, description}, ...].

    Scans the persona directory for *.yaml files, parses each, and returns
    a lightweight list for UI dropdowns. Heavy fields (soul_md) are omitted.
    """
    pdir = _persona_dir()
    if not pdir.is_dir():
        return []

    personas = []
    for yml in sorted(pdir.glob("*.yaml")):
        try:
            data = yaml.safe_load(yml.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                continue
            schema = str(data.get("schema", ""))
            if "persona/v1" not in schema:
                continue
            personas.append({
                "id": str(data.get("id", yml.stem)),
                "name": str(data.get("name", yml.stem)),
                "description": str(data.get("description", ""))[:120],
            })
        except Exception as exc:
            logger.warning("Failed to parse persona %s: %s", yml, exc)

    return personas


def load_persona(persona_id: str) -> Optional[dict[str, Any]]:
    """Load a full persona by ID. Returns None if not found or invalid."""
    pdir = _persona_dir()
    yml = pdir / f"{persona_id}.yaml"
    if not yml.is_file():
        return None

    try:
        data = yaml.safe_load(yml.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.warning("Failed to load persona %s: %s", persona_id, exc)
        return None

    if not isinstance(data, dict):
        return None

    return data


def render_persona_prompt(persona: dict[str, Any]) -> str:
    """Render a persona dict into a system prompt section.

    Takes the parsed YAML and produces a markdown block that gets
    prepended to the agent's system prompt. The LLM sees this as part
    of its identity instructions.
    """
    identity = persona.get("identity", {})
    if not isinstance(identity, dict):
        identity = {}

    parts = []

    display_name = str(identity.get("display_name", "")).strip()
    role = str(identity.get("role", "")).strip()
    personality = str(identity.get("personality", "")).strip()
    voice_tone = str(identity.get("voice_tone", "")).strip()
    voice_id = str(identity.get("voice_id", "")).strip()

    if display_name:
        parts.append(f"You are {display_name}.")
    if role:
        parts.append(f"Your role: {role}")
    if personality:
        parts.append(f"Personality: {personality}")
    if voice_tone:
        parts.append(f"Voice tone: {voice_tone}")

    soul_md = str(persona.get("soul_md", "")).strip()
    if soul_md:
        parts.append(soul_md)

    return "\n\n".join(p for p in parts if p)


def get_persona_prompt(persona_id: Optional[str]) -> str:
    """Convenience: load a persona by ID and return its prompt text.

    Returns empty string if persona_id is None, empty, or not found.
    Never raises — failures log and return "".
    """
    if not persona_id or not persona_id.strip():
        return ""

    persona = load_persona(persona_id.strip())
    if persona is None:
        return ""

    return render_persona_prompt(persona)