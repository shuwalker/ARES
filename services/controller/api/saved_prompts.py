"""Profile-scoped persistence for reusable conversation prompts.

This module owns prompt storage independently of any HTTP transport so the
FastAPI router and future native clients share one contract.
"""

from __future__ import annotations

import json
from pathlib import Path
import time
import uuid
from typing import Any


MAX_PROMPTS = 200
MAX_PROMPT_TEXT = 8_000


class SavedPromptError(ValueError):
    """A stable user-facing saved-prompt validation failure."""


def saved_prompts_path() -> Path:
    try:
        from api.profiles import get_active_ares_home

        root = Path(get_active_ares_home()).expanduser()
    except Exception:
        import os

        root = Path(os.getenv("ARES_HOME", str(Path.home() / ".ares"))).expanduser()
    return root / "webui" / "saved_prompts.json"


def load_saved_prompts() -> list[dict[str, Any]]:
    path = saved_prompts_path()
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return []
    if not isinstance(payload, list):
        return []
    return [row for row in payload if isinstance(row, dict)]


def save_saved_prompts(prompts: list[dict[str, Any]]) -> None:
    path = saved_prompts_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(prompts, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def create_saved_prompt(text: str, label: str = "") -> dict[str, Any]:
    normalized_text = str(text or "").strip()
    normalized_label = str(label or "").strip()
    if not normalized_text:
        raise SavedPromptError("text is required")
    if len(normalized_text) > MAX_PROMPT_TEXT:
        raise SavedPromptError("text too long (max 8000 chars)")

    prompts = load_saved_prompts()
    if len(prompts) >= MAX_PROMPTS:
        raise SavedPromptError("saved prompts limit reached (max 200)")

    prompt = {
        "id": uuid.uuid4().hex[:12],
        "label": normalized_label or normalized_text[:60],
        "text": normalized_text,
        "created_at": time.time(),
    }
    prompts.append(prompt)
    save_saved_prompts(prompts)
    return prompt


def delete_saved_prompt(prompt_id: str) -> None:
    normalized_id = str(prompt_id or "").strip()
    if not normalized_id:
        raise SavedPromptError("id is required")
    save_saved_prompts(
        [row for row in load_saved_prompts() if row.get("id") != normalized_id]
    )


# Compatibility aliases for tests and callers being migrated off api.routes.
_saved_prompts_path = saved_prompts_path
_load_saved_prompts = load_saved_prompts
_save_saved_prompts = save_saved_prompts


__all__ = [
    "MAX_PROMPTS",
    "MAX_PROMPT_TEXT",
    "SavedPromptError",
    "create_saved_prompt",
    "delete_saved_prompt",
    "load_saved_prompts",
    "save_saved_prompts",
    "saved_prompts_path",
]
