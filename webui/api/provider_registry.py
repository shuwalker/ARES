"""Explicit registry for external runtimes connected to ARES.

ARES owns none of the endpoints recorded here.  Each entry describes an
operator-selected connection to a separately managed provider.  Secret values
are deliberately excluded; ``credential_env`` names where a provider adapter
may resolve its credential at runtime.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from api.paths import _platform_default_ares_home

SCHEMA_VERSION = 1
REGISTRY_PATH_ENV = "ARES_PROVIDER_REGISTRY_PATH"


def provider_registry_path(environ: dict[str, str] | None = None) -> Path:
    source = os.environ if environ is None else environ
    override = str(source.get(REGISTRY_PATH_ENV) or "").strip()
    if override:
        return Path(override).expanduser()
    ares_home = str(source.get("ARES_HOME") or "").strip()
    return (Path(ares_home).expanduser() if ares_home else _platform_default_ares_home()) / "providers.json"


def empty_registry() -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSION, "providers": {}}


def _valid_endpoint(value: object) -> str:
    endpoint = str(value or "").strip().rstrip("/")
    if not endpoint:
        return ""
    parsed = urlparse(endpoint)
    if parsed.scheme not in {"http", "https", "ws", "wss"} or not parsed.hostname:
        return ""
    return endpoint


def normalize_provider(provider_id: str, raw: object) -> dict[str, Any] | None:
    provider_id = str(provider_id or "").strip().lower()
    if not provider_id or not isinstance(raw, dict):
        return None
    capabilities = sorted({
        str(item).strip()
        for item in raw.get("capabilities", [])
        if str(item).strip()
    })
    metadata = raw.get("metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    return {
        "id": provider_id,
        "enabled": bool(raw.get("enabled", False)),
        "kind": str(raw.get("kind") or "runtime").strip().lower(),
        "endpoint": _valid_endpoint(raw.get("endpoint")),
        "credential_env": str(raw.get("credential_env") or "").strip(),
        "capabilities": capabilities,
        "metadata": metadata,
    }


def load_provider_registry(
    path: Path | None = None,
    *,
    environ: dict[str, str] | None = None,
) -> dict[str, Any]:
    registry_path = path or provider_registry_path(environ)
    try:
        raw = json.loads(registry_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, ValueError, TypeError):
        return empty_registry()
    if not isinstance(raw, dict):
        return empty_registry()
    providers: dict[str, Any] = {}
    raw_providers = raw.get("providers")
    if isinstance(raw_providers, dict):
        for provider_id, entry in raw_providers.items():
            normalized = normalize_provider(str(provider_id), entry)
            if normalized is not None:
                providers[normalized["id"]] = normalized
    return {"schema_version": SCHEMA_VERSION, "providers": providers}


def configured_provider(
    provider_id: str,
    *,
    registry: dict[str, Any] | None = None,
    environ: dict[str, str] | None = None,
) -> dict[str, Any] | None:
    data = registry if registry is not None else load_provider_registry(environ=environ)
    providers = data.get("providers") if isinstance(data, dict) else None
    entry = providers.get(str(provider_id).strip().lower()) if isinstance(providers, dict) else None
    return entry if isinstance(entry, dict) and entry.get("enabled") else None


def provider_endpoint(
    provider_id: str,
    *,
    registry: dict[str, Any] | None = None,
    environ: dict[str, str] | None = None,
) -> str:
    entry = configured_provider(provider_id, registry=registry, environ=environ)
    return str(entry.get("endpoint") or "") if entry else ""


def save_provider(
    provider_id: str,
    entry: dict[str, Any],
    *,
    path: Path | None = None,
    environ: dict[str, str] | None = None,
) -> dict[str, Any]:
    normalized = normalize_provider(provider_id, entry)
    if normalized is None:
        raise ValueError("A provider ID and object are required.")
    if entry.get("endpoint") and not normalized["endpoint"]:
        raise ValueError("Provider endpoint must be an HTTP(S) or WebSocket URL.")
    registry_path = path or provider_registry_path(environ)
    registry = load_provider_registry(registry_path)
    registry["providers"][normalized["id"]] = normalized
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=".providers-", suffix=".json", dir=registry_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(registry, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary_name, registry_path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
    return normalized


def remove_provider(
    provider_id: str,
    *,
    path: Path | None = None,
    environ: dict[str, str] | None = None,
) -> bool:
    registry_path = path or provider_registry_path(environ)
    registry = load_provider_registry(registry_path)
    removed = registry["providers"].pop(str(provider_id or "").strip().lower(), None) is not None
    if removed:
        registry_path.parent.mkdir(parents=True, exist_ok=True)
        registry_path.write_text(
            json.dumps(registry, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return removed
