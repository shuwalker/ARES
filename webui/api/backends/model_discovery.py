"""Discover configured LLM providers and installed local models.

auth/credential pool, Ollama local tags, and Jaeger GGUF installs.

These catalogs feed adapter ``inventory()`` so Chat can list only what
is actually configured or installed for that backend.
"""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from api.backends.catalog import infer_model_location, model_entry

logger = logging.getLogger(__name__)

def _safe_yaml_load(path: Path) -> dict[str, Any]:
    try:
        import yaml  # type: ignore

        if not path.is_file():
            return {}
        with path.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        return data if isinstance(data, dict) else {}
    except Exception:
        logger.debug("YAML load failed for %s", path, exc_info=True)
        return {}


def _safe_json_load(path: Path) -> dict[str, Any]:
    try:
        if not path.is_file():
            return {}
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        logger.debug("JSON load failed for %s", path, exc_info=True)
        return {}


def list_ollama_local_models(
    *,
    base_url: str = "http://127.0.0.1:11434",
    timeout: float = 1.5,
) -> list[dict[str, Any]]:
    """Installed local Ollama models via ``/api/tags``."""
    url = base_url.rstrip("/") + "/api/tags"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="replace") or "{}")
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
        return []
    models: list[dict[str, Any]] = []
    for row in payload.get("models") or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or row.get("model") or "").strip()
        if not name:
            continue
        models.append(
            model_entry(
                id=name,
                label=name,
                location="local",
                provider="ollama",
                in_use=False,
                source=f"{url}",
                notes="Installed local Ollama model.",
            )
        )
    return models


def _jaeger_roots() -> list[Path]:
    roots: list[Path] = []
    for env_key in ("ARES_JAEGER_HOME", "JAEGER_HOME"):
        raw = os.environ.get(env_key)
        if raw:
            roots.append(Path(raw).expanduser())
    # Generic conventional locations only. A maintainer's own clone path must
    # never be a fallback: it leaks a username into a public repo and is dead
    # weight for every other user. Point ARES_JAEGER_HOME/JAEGER_HOME at a
    # non-standard checkout instead.
    roots.extend(
        [
            Path.home() / "jaeger",
            Path.home() / ".jaeger",
            Path.home() / "JaegerAI",
        ]
    )
    # de-dupe existing
    out: list[Path] = []
    seen: set[str] = set()
    for r in roots:
        key = str(r.resolve()) if r.exists() else str(r)
        if key in seen:
            continue
        seen.add(key)
        if r.exists():
            out.append(r)
    return out


def list_jaeger_installed_gguf(jaeger_home: Path | None = None) -> list[dict[str, Any]]:
    """Scan ``.jaeger_os/models/<id>/*.gguf`` installs."""
    homes = [jaeger_home] if jaeger_home else _jaeger_roots()
    models: list[dict[str, Any]] = []
    seen: set[str] = set()
    for home in homes:
        models_dir = home / ".jaeger_os" / "models"
        if not models_dir.is_dir():
            continue
        for child in sorted(models_dir.iterdir()):
            if not child.is_dir():
                continue
            ggufs = list(child.glob("*.gguf"))
            if not ggufs:
                continue
            mid = child.name
            if mid in seen:
                continue
            seen.add(mid)
            file_name = ggufs[0].name
            models.append(
                model_entry(
                    id=file_name if file_name else mid,
                    label=file_name or mid,
                    location="local",
                    provider="local",
                    in_use=False,
                    source=str(ggufs[0]),
                    notes=f"Installed GGUF under {child.name}",
                )
            )
    return models


def discover_jros_models(
    *,
    instance: str | None = None,
    gateway_health: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Configured + installed models/providers for JaegerAI/JROS."""
    health = gateway_health or {}
    inst = str(instance or health.get("instance") or "jarvis").strip() or "jarvis"
    models: list[dict[str, Any]] = []
    seen: set[str] = set()
    providers: list[dict[str, Any]] = []

    def _push(entry: dict[str, Any]) -> None:
        mid = str(entry.get("id") or "")
        if not mid or mid in seen or mid.startswith("("):
            return
        seen.add(mid)
        models.append(entry)

    # Live gateway model
    live_model = str(health.get("model") or "").strip()
    live_provider = str(health.get("provider") or "local").strip() or "local"
    if live_model:
        _push(
            model_entry(
                id=live_model,
                label=live_model,
                location=infer_model_location(live_provider, live_model),
                provider=live_provider,
                in_use=True,
                source="jros_gateway:/v1/health",
                notes="Currently loaded by gateway",
            )
        )

    # Instance config
    for home in _jaeger_roots():
        cfg_path = home / ".jaeger_os" / "instances" / inst / "config.yaml"
        cfg = _safe_yaml_load(cfg_path)
        if not cfg:
            continue
        mblock = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
        model_path = str(mblock.get("model_path") or "").strip()
        backend = str(mblock.get("backend") or "").strip() or "llama_cpp_python"
        if model_path:
            # Prefer matching gguf filename if present
            gguf_dir = home / ".jaeger_os" / "models" / model_path
            gguf_files = list(gguf_dir.glob("*.gguf")) if gguf_dir.is_dir() else []
            mid = gguf_files[0].name if gguf_files else model_path
            _push(
                model_entry(
                    id=mid,
                    label=mid,
                    location="local",
                    provider="local",
                    in_use=(mid == live_model or model_path in live_model.lower()),
                    source=str(cfg_path),
                    notes=f"instance model_path ({backend})",
                )
            )
        deep = cfg.get("deep_think") if isinstance(cfg.get("deep_think"), dict) else {}
        coder = str(deep.get("coder_model") or "").strip()
        if coder:
            _push(
                model_entry(
                    id=coder,
                    label=coder,
                    location="local",
                    provider="local",
                    in_use=False,
                    source=str(cfg_path) + "#deep_think",
                    notes="deep_think.coder_model",
                )
            )
        external = cfg.get("external_model") if isinstance(cfg.get("external_model"), dict) else {}
        if external.get("enabled"):
            ext_model = str(external.get("model") or "").strip()
            ext_prov = str(external.get("provider") or "external").strip()
            if ext_model:
                _push(
                    model_entry(
                        id=ext_model,
                        label=ext_model,
                        location=infer_model_location(ext_prov, ext_model),
                        provider=ext_prov,
                        in_use=False,
                        source=str(cfg_path) + "#external_model",
                        notes=f"external_model @ {external.get('base_url') or ''}".strip(),
                    )
                )
            providers.append(
                {
                    "id": ext_prov,
                    "label": ext_prov,
                    "status": "configured",
                    "source": str(cfg_path),
                    "notes": "external_model.enabled",
                }
            )
        providers.append(
            {
                "id": "local",
                "label": "Local GGUF / llama.cpp",
                "status": "configured",
                "source": str(cfg_path),
                "notes": backend,
            }
        )
        break  # first home with instance config wins for providers

    # Installed GGUF packages
    for m in list_jaeger_installed_gguf():
        _push(m)

    # Local ollama as optional provider for JROS external setups
    ollama_models = list_ollama_local_models()
    if ollama_models:
        providers.append(
            {
                "id": "ollama",
                "label": "Ollama (local daemon)",
                "status": "configured",
                "source": "http://127.0.0.1:11434/api/tags",
                "notes": f"{len(ollama_models)} model(s)",
            }
        )

    # de-dupe providers
    prov_map: dict[str, dict[str, Any]] = {}
    for p in providers:
        prov_map[p["id"]] = p
    if live_provider and live_provider not in prov_map:
        prov_map[live_provider] = {
            "id": live_provider,
            "label": live_provider,
            "status": "configured",
            "source": "jros_gateway",
            "notes": "active gateway provider",
        }

    return {
        "models": models,
        "providers": sorted(prov_map.values(), key=lambda p: p["id"]),
        "default": {
            "model": live_model or None,
            "provider": live_provider or "local",
            "instance": inst,
        },
    }
