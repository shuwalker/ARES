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
    # Runtime compatibility aliases are normalized while unrelated provider
    # and tool IDs pass through unchanged.
    from api.backend_catalog import BACKEND_ALIASES

    provider_id = BACKEND_ALIASES.get(provider_id, provider_id)
    if not provider_id or not isinstance(raw, dict):
        return None
    # Only real sequences are iterated. A bare string is iterable, so a
    # hand-edited `"capabilities": "conversation"` used to explode into ten
    # single-character capabilities that then passed validation.
    raw_capabilities = raw.get("capabilities")
    if not isinstance(raw_capabilities, (list, tuple, set, frozenset)):
        raw_capabilities = ()
    capabilities = sorted({
        str(item).strip()
        for item in raw_capabilities
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


class ProviderRegistryCorrupt(RuntimeError):
    """The registry file exists but could not be parsed.

    Distinct from "no registry yet" so callers can refuse to overwrite
    configuration they were unable to read.
    """

    def __init__(self, path: Path, cause: Exception) -> None:
        super().__init__(f"{path} could not be parsed: {cause}")
        self.path = path
        self.cause = cause


def load_provider_registry(
    path: Path | None = None,
    *,
    environ: dict[str, str] | None = None,
    strict: bool = False,
) -> dict[str, Any]:
    """Read the registry, treating a missing file as empty.

    With ``strict``, an unreadable *existing* file raises
    :class:`ProviderRegistryCorrupt` instead of silently reading as empty.
    Writers use that so a parse failure cannot be laundered into an empty
    registry and then written back over every configured provider.
    """
    registry_path = path or provider_registry_path(environ)
    try:
        raw = json.loads(registry_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return empty_registry()
    except (OSError, ValueError, TypeError) as exc:
        if strict:
            raise ProviderRegistryCorrupt(registry_path, exc) from exc
        return empty_registry()
    if not isinstance(raw, dict):
        if strict:
            raise ProviderRegistryCorrupt(
                registry_path, TypeError(f"expected a JSON object, got {type(raw).__name__}")
            )
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
    from api.backend_catalog import BACKEND_ALIASES

    requested = str(provider_id).strip().lower()
    requested = BACKEND_ALIASES.get(requested, requested)
    entry = providers.get(requested) if isinstance(providers, dict) else None
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
    # strict=True: a read failure must not be laundered into an empty registry
    # that then overwrites every other configured provider. One truncated write
    # or hand-edit typo used to silently erase the whole file on the next save.
    registry = load_provider_registry(registry_path, strict=True)
    registry["providers"][normalized["id"]] = normalized
    _write_registry(registry_path, registry)
    return normalized


def remove_provider(
    provider_id: str,
    *,
    path: Path | None = None,
    environ: dict[str, str] | None = None,
) -> bool:
    registry_path = path or provider_registry_path(environ)
    registry = load_provider_registry(registry_path, strict=True)
    from api.backend_catalog import BACKEND_ALIASES

    requested = str(provider_id or "").strip().lower()
    requested = BACKEND_ALIASES.get(requested, requested)
    removed = registry["providers"].pop(requested, None) is not None
    if removed:
        _write_registry(registry_path, registry)
    return removed


def _write_registry(registry_path: Path, registry: dict[str, Any]) -> None:
    """Persist the registry atomically.

    Shared by both writers so a removal cannot be interrupted into a truncated
    file the way a plain ``write_text`` could — which would then be unreadable,
    and (before ``strict``) silently emptied on the following save.
    """
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        prefix=".providers-", suffix=".json", dir=registry_path.parent
    )
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
