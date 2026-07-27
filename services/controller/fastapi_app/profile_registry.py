"""Small, profile-scoped JSON registries with crash-safe mutation semantics."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from threading import RLock
from typing import Callable, TypeVar


T = TypeVar("T")
_LOCK = RLock()


def _read_list(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []
    return value if isinstance(value, list) else []


def read_json_list(path: Path) -> list[dict]:
    with _LOCK:
        return [dict(item) for item in _read_list(path) if isinstance(item, dict)]


def mutate_json_list(path: Path, mutation: Callable[[list[dict]], T]) -> T:
    """Run a read-modify-write transaction and atomically replace the registry."""
    with _LOCK:
        path.parent.mkdir(parents=True, exist_ok=True)
        items = [dict(item) for item in _read_list(path) if isinstance(item, dict)]
        result = mutation(items)
        descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(items, handle, indent=2)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
        return result
