"""JROS persona/character injection — loads YAML from JROS and builds system prompt prefix.

Supports two JROS schema versions:
  - character/v1 (JROS 0.5+): jaeger_os/personality/characters/<id>/character.yaml
    Uses prompt.custom_instructions, prompt.soul, identity.role, identity.voice_tone
  - persona/v1 (legacy): jaeger_os/agent/personas/<id>.yaml
    Uses soul_md, identity.display_name, identity.personality

Scans both directories, merges results. Zero coupling to JROS runtime —
this only reads YAML files. The JROS daemon doesn't need to be running.
The persona is pure prompt text.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Optional

import yaml

logger = logging.getLogger(__name__)

# JROS character/persona directories (checked in order).
_CHARACTER_DIR = os.path.expanduser("~/GitHub/JROS/jaeger_os/personality/characters")
_LEGACY_PERSONA_DIR = os.path.expanduser("~/GitHub/JROS/jaeger_os/agent/personas")

# Env override for portability.
_CHARACTER_DIR_ENV = "ARES_CHARACTER_DIR"
_PERSONA_DIR_ENV = "ARES_PERSONA_DIR"


def _character_dir() -> Path:
    raw = os.getenv(_CHARACTER_DIR_ENV, _CHARACTER_DIR)
    return Path(raw).expanduser()


def _legacy_persona_dir() -> Path:
    raw = os.getenv(_PERSONA_DIR_ENV, _LEGACY_PERSONA_DIR)
    return Path(raw).expanduser()


def _parse_character_v1(data: dict, yml_path: Path) -> Optional[dict[str, Any]]:
    """Parse a character/v1 YAML into a normalized persona dict."""
    identity = data.get("identity", {})
    if not isinstance(identity, dict):
        identity = {}
    prompt = data.get("prompt", {})
    if not isinstance(prompt, dict):
        prompt = {}
    return {
        "schema": "character/v1",
        "id": str(data.get("id", yml_path.parent.name)),
        "name": str(data.get("name", yml_path.parent.name)),
        "description": str(data.get("description", ""))[:120],
        "identity": {
            "display_name": str(data.get("name", "")),
            "role": str(identity.get("role", "")),
            "voice_tone": str(identity.get("voice_tone", "")),
            "voice_id": str(identity.get("voice_id", "")),
        },
        "custom_instructions": str(prompt.get("custom_instructions", "")),
        "soul": str(prompt.get("soul", "")),
        "backstory": str(prompt.get("backstory", "")),
        "speech_patterns": prompt.get("speech_patterns", []),
    }


def _parse_persona_v1(data: dict, yml_path: Path) -> Optional[dict[str, Any]]:
    """Parse a legacy persona/v1 YAML into a normalized persona dict."""
    identity = data.get("identity", {})
    if not isinstance(identity, dict):
        identity = {}
    return {
        "schema": "persona/v1",
        "id": str(data.get("id", yml_path.stem)),
        "name": str(data.get("name", yml_path.stem)),
        "description": str(data.get("description", ""))[:120],
        "identity": {
            "display_name": str(identity.get("display_name", "")),
            "role": str(identity.get("role", "")),
            "personality": str(identity.get("personality", "")),
            "voice_tone": str(identity.get("voice_tone", "")),
            "voice_id": str(identity.get("voice_id", "")),
        },
        "soul_md": str(data.get("soul_md", "")),
    }


def list_personas() -> list[dict[str, str]]:
    """Return all available personas as [{id, name, description, schema}, ...].

    Scans both character/v1 and legacy persona/v1 directories.
    """
    personas: list[dict[str, str]] = []
    seen_ids: set[str] = set()

    # character/v1 — each subdirectory has a character.yaml
    cdir = _character_dir()
    if cdir.is_dir():
        for yml in sorted(cdir.glob("*/character.yaml")):
            try:
                data = yaml.safe_load(yml.read_text(encoding="utf-8"))
                if not isinstance(data, dict):
                    continue
                schema = str(data.get("schema", ""))
                if "character/v1" not in schema:
                    continue
                parsed = _parse_character_v1(data, yml)
                if parsed and parsed["id"] not in seen_ids:
                    seen_ids.add(parsed["id"])
                    personas.append({
                        "id": parsed["id"],
                        "name": parsed["name"],
                        "description": parsed["description"],
                        "schema": "character/v1",
                    })
            except Exception as exc:
                logger.warning("Failed to parse character %s: %s", yml, exc)

    # legacy persona/v1 — flat directory of *.yaml files
    pdir = _legacy_persona_dir()
    if pdir.is_dir():
        for yml in sorted(pdir.glob("*.yaml")):
            try:
                data = yaml.safe_load(yml.read_text(encoding="utf-8"))
                if not isinstance(data, dict):
                    continue
                schema = str(data.get("schema", ""))
                if "persona/v1" not in schema:
                    continue
                parsed = _parse_persona_v1(data, yml)
                if parsed and parsed["id"] not in seen_ids:
                    seen_ids.add(parsed["id"])
                    personas.append({
                        "id": parsed["id"],
                        "name": parsed["name"],
                        "description": parsed["description"],
                        "schema": "persona/v1",
                    })
            except Exception as exc:
                logger.warning("Failed to parse persona %s: %s", yml, exc)

    return personas


def load_persona(persona_id: str) -> Optional[dict[str, Any]]:
    """Load a full persona by ID. Checks character/v1 first, then legacy.

    Returns the normalized dict (with a 'schema' field) or None if not found.
    """
    # Try character/v1 first
    cdir = _character_dir()
    char_yml = cdir / persona_id / "character.yaml"
    if char_yml.is_file():
        try:
            data = yaml.safe_load(char_yml.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "character/v1" in str(data.get("schema", "")):
                return _parse_character_v1(data, char_yml)
        except Exception as exc:
            logger.warning("Failed to load character %s: %s", persona_id, exc)

    # Fall back to legacy persona/v1
    pdir = _legacy_persona_dir()
    legacy_yml = pdir / f"{persona_id}.yaml"
    if legacy_yml.is_file():
        try:
            data = yaml.safe_load(legacy_yml.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "persona/v1" in str(data.get("schema", "")):
                return _parse_persona_v1(data, legacy_yml)
        except Exception as exc:
            logger.warning("Failed to load persona %s: %s", persona_id, exc)

    return None


def render_persona_prompt(persona: dict[str, Any]) -> str:
    """Render a normalized persona dict into a system prompt section.

    Handles both character/v1 and persona/v1 schemas. Produces a markdown
    block prepended to the agent's system prompt.
    """
    schema = persona.get("schema", "")
    identity = persona.get("identity", {})
    if not isinstance(identity, dict):
        identity = {}

    parts = []

    if schema == "character/v1":
        # Character/v1: custom_instructions is the main prompt, soul is supplementary
        display_name = str(identity.get("display_name", "")).strip()
        role = str(identity.get("role", "")).strip()
        voice_tone = str(identity.get("voice_tone", "")).strip()
        custom_instructions = str(persona.get("custom_instructions", "")).strip()
        soul = str(persona.get("soul", "")).strip()
        speech_patterns = persona.get("speech_patterns", [])

        if custom_instructions:
            parts.append(custom_instructions)
        elif display_name:
            parts.append(f"You are {display_name}.")
            if role:
                parts.append(f"Your role: {role}")

        if voice_tone:
            parts.append(f"Voice tone: {voice_tone}")

        if speech_patterns and isinstance(speech_patterns, list):
            patterns = "; ".join(str(p) for p in speech_patterns[:5] if p)
            if patterns:
                parts.append(f"Speech patterns: {patterns}")

        if soul:
            parts.append(soul)

    else:
        # Legacy persona/v1
        display_name = str(identity.get("display_name", "")).strip()
        role = str(identity.get("role", "")).strip()
        personality = str(identity.get("personality", "")).strip()
        voice_tone = str(identity.get("voice_tone", "")).strip()

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