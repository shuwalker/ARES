"""Operator-specific email assistant configuration.

Everything in mail_assistant.py that identifies a person or a personal
filesystem location is read from here — never hardcoded. All values are
optional; the assistant degrades gracefully (skips NAS archiving, uses a
generic reply signature) when they're unset.

Configure via environment variables, or a JSON file at
``~/.ares/mail_config.json`` with the same keys (env vars take precedence):

    {
      "assistant_name": "Your Name",
      "nas_archive_path": "/Volumes/MyDrive/Mail",
      "keep_addresses": ["family@example.com"],
      "work_domains": ["mycompany.com"]
    }
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import List

_CONFIG_FILE = Path.home() / ".ares" / "mail_config.json"


def _load_file_config() -> dict:
    if not _CONFIG_FILE.exists():
        return {}
    try:
        data = json.loads(_CONFIG_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


_FILE_CONFIG = _load_file_config()


def assistant_name() -> str:
    """Name used in LLM prompts (drafting/classifying). Generic if unset."""
    return os.environ.get("ARES_MAIL_ASSISTANT_NAME") or str(
        _FILE_CONFIG.get("assistant_name") or ""
    )


def nas_archive_path() -> str:
    """Optional filesystem path for archived email exports. Empty disables NAS save."""
    return os.environ.get("ARES_MAIL_NAS_PATH") or str(
        _FILE_CONFIG.get("nas_archive_path") or ""
    )


def extra_keep_addresses() -> List[str]:
    """Additional sender addresses/domains that should never be classified as junk."""
    env_value = os.environ.get("ARES_MAIL_KEEP_ADDRESSES", "")
    if env_value:
        return [v.strip() for v in env_value.split(",") if v.strip()]
    value = _FILE_CONFIG.get("keep_addresses") or []
    return [str(v) for v in value] if isinstance(value, list) else []


def extra_work_domains() -> List[str]:
    """Employer domain(s) to file under the 'Work' archive category."""
    env_value = os.environ.get("ARES_MAIL_WORK_DOMAINS", "")
    if env_value:
        return [v.strip() for v in env_value.split(",") if v.strip()]
    value = _FILE_CONFIG.get("work_domains") or []
    return [str(v) for v in value] if isinstance(value, list) else []
