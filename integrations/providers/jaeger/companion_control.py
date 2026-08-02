"""Normalized ARES control surface for the selected JaegerAI Companion.

JaegerAI owns agent identity, characters, and their persistence. ARES never
writes those files; it asks the independently versioned peer to read or mutate
them through bridge protocol v1.
"""
from __future__ import annotations

from typing import Any


class CompanionControlError(RuntimeError):
    """The selected JaegerAI Companion could not satisfy a control request."""


def _as_dict(value: Any) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def _character_summary(value: Any) -> dict[str, Any]:
    row = _as_dict(value)
    return {
        "id": str(row.get("id") or ""),
        "name": str(row.get("name") or row.get("id") or ""),
        "role": str(row.get("role") or ""),
        "voice_tone": str(row.get("voice_tone") or ""),
        "voice_id": str(row.get("voice_id") or ""),
        "active": bool(row.get("active")),
        "bound": bool(row.get("bound")),
    }


def companion_snapshot() -> dict[str, Any]:
    """Return the live identity and character exposed by JaegerAI."""
    try:
        from api.providers.jaeger.gateway_streaming import query_local_companion
        from api.providers.jaeger.paths import jaeger_home, jros_instance_name

        identity = _as_dict(query_local_companion("identity"))
        character = _as_dict(query_local_companion("character"))
        characters_raw = query_local_companion("characters")
        characters = [
            _character_summary(row)
            for row in (characters_raw if isinstance(characters_raw, list) else [])
        ]
        active_id = str(character.get("id") or "")
        active_summary = next((row for row in characters if row["id"] == active_id), {})
        return {
            "contract_version": 1,
            "dependency": {
                "product": "JaegerAI",
                "root": str(jaeger_home()),
                "transport": "bridge",
            },
            "agent": {
                "id": str(identity.get("instance") or jros_instance_name() or ""),
                "name": str(identity.get("agent_name") or ""),
                "model": identity.get("model"),
                "avatar": identity.get("avatar"),
            },
            "character": {
                **_character_summary(character),
                "active": bool(active_summary.get("active", True)),
                "bound": bool(active_summary.get("bound", False)),
                "custom_instructions": str(character.get("custom_instructions") or ""),
            },
            "characters": characters,
        }
    except Exception as exc:
        raise CompanionControlError(str(exc)) from exc


def update_companion(*, name: str | None = None, character_id: str | None = None) -> dict[str, Any]:
    """Apply supported Companion edits through JaegerAI and read back truth."""
    clean_name = str(name or "").strip()
    clean_character = str(character_id or "").strip()
    if not clean_name and not clean_character:
        raise CompanionControlError("No Companion changes were supplied.")
    try:
        from api.providers.jaeger.gateway_streaming import command_local_companion

        if clean_name:
            command_local_companion("save_identity", {"name": clean_name})
        if clean_character:
            # Selecting changes the live character now; binding makes the same
            # choice survive the next JaegerAI launch.
            command_local_companion("select_character", {"id": clean_character})
            command_local_companion("make_default", {"id": clean_character})
        return companion_snapshot()
    except Exception as exc:
        raise CompanionControlError(str(exc)) from exc
