"""Profile-scoped persistence for small first-party product modules.

This is intentionally not a generic filesystem endpoint. Only registered ARES
modules can store bounded JSON documents, and writes use optimistic revisions
plus an atomic replace so two windows cannot silently overwrite one another.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import threading
from typing import Any


MAX_STATE_BYTES = 2 * 1024 * 1024
REGISTERED_MODULES = frozenset({"board", "canvas", "timeline", "issues", "cases", "goals", "daily-goals"})
_MODULE_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
_lock = threading.RLock()


class ProductStateError(RuntimeError):
    pass


class ProductStateConflict(ProductStateError):
    pass


def _module_name(module: str) -> str:
    value = str(module or "").strip().lower()
    if not _MODULE_RE.fullmatch(value) or value not in REGISTERED_MODULES:
        raise ProductStateError("Unknown product-state module")
    return value


def _state_path(profile: str | None, module: str) -> Path:
    from api.profiles import get_ares_home_for_profile

    root = Path(get_ares_home_for_profile(profile)).expanduser().resolve()
    return root / "webui" / "product-state" / f"{_module_name(module)}.json"


def read_product_state(profile: str | None, module: str) -> dict[str, Any]:
    path = _state_path(profile, module)
    with _lock:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {"module": _module_name(module), "revision": 0, "state": {}}
        except (OSError, json.JSONDecodeError) as exc:
            raise ProductStateError("Product state could not be read") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("state"), dict):
        raise ProductStateError("Product state is invalid")
    return {
        "module": _module_name(module),
        "revision": max(0, int(payload.get("revision") or 0)),
        "state": payload["state"],
    }


def write_product_state(
    profile: str | None,
    module: str,
    state: dict[str, Any],
    *,
    expected_revision: int | None = None,
) -> dict[str, Any]:
    name = _module_name(module)
    if not isinstance(state, dict):
        raise ProductStateError("Product state must be an object")
    path = _state_path(profile, name)
    with _lock:
        current = read_product_state(profile, name)
        if expected_revision is not None and current["revision"] != expected_revision:
            raise ProductStateConflict("Product state changed in another window")
        payload = {"revision": current["revision"] + 1, "state": state}
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_STATE_BYTES:
            raise ProductStateError("Product state exceeds the 2 MB limit")
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(f".{path.name}.{os.getpid()}.{threading.get_ident()}.tmp")
        try:
            with temporary.open("wb") as handle:
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
    return {"module": name, **payload}
