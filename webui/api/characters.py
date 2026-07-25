"""JROS character detail loader — serves full character data including traits, lore, and card URL.

Reads character YAMLs from <JROS repo>/jaeger_os/personality/characters/<id>/character.yaml
(schema: character/v1).  Designed as a companion to api.persona — persona handles
prompt rendering, this module exposes the raw data for the WebUI character browser.

The JROS repo location is resolved through ``api.jros_paths``. ``ARES_JROS_DIR``
and ``ARES_CHARACTER_DIR`` still win, but common local checkouts such as
``~/GitHub/JROS`` are discovered automatically for developer installs.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

import yaml

from api.jros_paths import character_dir

logger = logging.getLogger(__name__)


def _character_dir() -> Path:
    return character_dir()


def _parse_character(data: dict, yml_path: Path) -> Optional[dict[str, Any]]:
    """Parse a character/v1 YAML into a full detail dict for the API."""
    identity = data.get("identity") or {}
    if not isinstance(identity, dict):
        identity = {}
    prompt = data.get("prompt") or {}
    if not isinstance(prompt, dict):
        prompt = {}
    traits = data.get("traits") or {}
    if not isinstance(traits, dict):
        traits = {}
    lore = data.get("lore") or {}
    if not isinstance(lore, dict):
        lore = {}
    assets = data.get("assets") or {}
    if not isinstance(assets, dict):
        assets = {}

    char_id = str(data.get("id", yml_path.parent.name))

    return {
        "id": char_id,
        "name": str(data.get("name", char_id)),
        "description": str(data.get("description", "")),
        "role": str(identity.get("role", "")),
        "voice_tone": str(identity.get("voice_tone", "")),
        "level": int(data.get("level", 1)),
        "revision": float(data.get("revision", 1.0)),
        "card_url": "/assets/ares-app-icon.png",
        "traits": {
            "hexaco": traits.get("hexaco") or {},
            "special": traits.get("special") or {},
            "expression": traits.get("expression") or {},
            "domains": traits.get("domains") or {},
        },
        "lore": {
            "quotes": lore.get("quotes") or [],
            "mannerisms": lore.get("mannerisms") or [],
            "ideals": lore.get("ideals") or [],
            "behaviors": lore.get("behaviors") or [],
        },
        "custom_instructions": str(prompt.get("custom_instructions", "")),
        "backstory": str(prompt.get("backstory", "")),
        "speech_patterns": prompt.get("speech_patterns") or [],
    }


def list_characters() -> list[dict[str, Any]]:
    """Return all character/v1 entries with full detail data.

    Scans the character directory for subdirs containing character.yaml.
    """
    characters: list[dict[str, Any]] = []
    cdir = _character_dir()
    if not cdir.is_dir():
        logger.warning("Character directory not found: %s", cdir)
        return characters

    for yml in sorted(cdir.glob("*/character.yaml")):
        try:
            data = yaml.safe_load(yml.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                continue
            schema = str(data.get("schema", ""))
            if "character/v1" not in schema:
                continue
            char = _parse_character(data, yml)
            if char:
                characters.append(char)
        except Exception as exc:
            logger.warning("Failed to parse character %s: %s", yml, exc)

    return characters


def get_character(char_id: str) -> Optional[dict[str, Any]]:
    """Return a single character by ID, or None if not found."""
    cdir = _character_dir()
    yml_path = cdir / char_id / "character.yaml"
    if not yml_path.is_file():
        return None
    try:
        data = yaml.safe_load(yml_path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return None
        schema = str(data.get("schema", ""))
        if "character/v1" not in schema:
            return None
        return _parse_character(data, yml_path)
    except Exception as exc:
        logger.warning("Failed to load character %s: %s", char_id, exc)
        return None
