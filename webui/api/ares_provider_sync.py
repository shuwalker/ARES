"""Synchronize LLM provider settings between Hermes and JROS configs.

This module intentionally writes only provider metadata (provider/model/base URL
and API-key environment variable names). It never writes secret values or
credential files.
"""

from __future__ import annotations

import os
import shutil
import urllib.error
import urllib.request
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterable

import yaml

from api.jros_paths import expand_path, jros_config_path


PROVIDER_PRESETS: dict[str, dict[str, str | None]] = {
    "gemini": {
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "api_key_env": "GOOGLE_API_KEY",
    },
    "openai": {
        "base_url": "https://api.openai.com/v1",
        "api_key_env": "OPENAI_API_KEY",
    },
    "anthropic": {
        "base_url": "https://api.anthropic.com",
        "api_key_env": "ANTHROPIC_API_KEY",
    },
    "ollama-cloud": {
        "base_url": "https://ollama.com/v1",
        "api_key_env": "OLLAMA_API_KEY",
    },
    "ollama": {
        # Ollama's OpenAI-compatible endpoint.  Keep the /v1 suffix here so
        # Hermes, JROS, and the ARES bridge all receive the same URL shape.
        "base_url": "http://127.0.0.1:11434/v1",
        "api_key_env": None,
    },
    # ``ollama launch`` creates this named Hermes provider.  It is still the
    # local Ollama runtime, but preserving the name lets ARES round-trip the
    # user's existing Hermes model selection instead of silently changing it
    # to a different provider lane.
    "ollama-launch": {
        "base_url": "http://127.0.0.1:11434/v1",
        "api_key_env": None,
    },
    "lmstudio": {
        "base_url": "http://localhost:1234/v1",
        "api_key_env": None,
    },
}

JROS_FALLBACK_PROVIDER_MAP: dict[str, str | None] = {
    "anthropic": "anthropic",
    "gemini": "gemini",
    "lmstudio": "lmstudio",
    "ollama": "ollama",
    "ollama-launch": "ollama",
    "ollama-cloud": "ollama-cloud",
    "ollama-local": "ollama",
    "local": "ollama",
    "openai": "openai",
    # Hermes OAuth provider slugs are not runnable by JROS today.
    "openai-codex": None,
    "xai-oauth": None,
}


def provider_runtime_status(provider: str, base_url: str | None = None) -> dict[str, Any]:
    """Describe whether a configured provider can actually be reached.

    Provider configuration is intentionally usable before a runtime is started;
    this probe is informational and never rewrites config or installs software.
    That distinction lets ARES work on machines with no Ollama while giving a
    precise "installed, start Ollama" state when a local model is selected.
    """
    normalized = str(provider or "").strip().lower()
    if normalized in {"ollama", "ollama-launch", "ollama-local", "local"}:
        endpoint = str(base_url or PROVIDER_PRESETS["ollama"]["base_url"] or "").strip().rstrip("/")
        api_root = endpoint[:-3] if endpoint.endswith("/v1") else endpoint
        installed = bool(shutil.which("ollama")) or any(
            path.exists() for path in (
                Path("/Applications/Ollama.app"),
                Path.home() / "Applications" / "Ollama.app",
            )
        )
        try:
            with urllib.request.urlopen(f"{api_root}/api/tags", timeout=1.5) as response:
                payload = yaml.safe_load(response.read().decode("utf-8")) or {}
            models = payload.get("models") if isinstance(payload, dict) else []
            model_count = len(models) if isinstance(models, list) else 0
            return {
                "provider": normalized,
                "available": True,
                "state": "running",
                "installed": installed,
                "model_count": model_count,
                "base_url": endpoint,
            }
        except Exception:
            return {
                "provider": normalized,
                "available": False,
                "state": "installed_not_running" if installed else "not_installed",
                "installed": installed,
                "model_count": 0,
                "base_url": endpoint,
            }
    if normalized == "ollama-cloud":
        try:
            from api.providers import provider_has_usable_credential

            configured = bool(provider_has_usable_credential("ollama-cloud"))
        except Exception:
            configured = bool(os.getenv("OLLAMA_API_KEY", "").strip())
        return {
            "provider": normalized,
            "available": configured,
            "state": "configured" if configured else "missing_credentials",
            "installed": True,
            "model_count": None,
            "base_url": str(base_url or PROVIDER_PRESETS[normalized]["base_url"] or "").strip(),
        }
    # Other API providers are credential/configuration concerns; their network
    # request is intentionally deferred until the user sends a turn.
    return {
        "provider": normalized,
        "available": True,
        "state": "configured",
        "installed": True,
        "model_count": None,
        "base_url": str(base_url or "").strip() or None,
    }

def resolve_jros_config_path() -> Path:
    """Compatibility wrapper for callers/tests; use api.jros_paths.jros_config_path."""
    return jros_config_path()


def load_yaml_config(path: str | os.PathLike[str]) -> dict[str, Any]:
    config_path = Path(path).expanduser()
    if not config_path.exists():
        return {}
    data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def save_yaml_config(path: str | os.PathLike[str], data: dict[str, Any]) -> None:
    config_path = Path(path).expanduser()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def _normalize_provider(provider: str) -> str:
    normalized = str(provider or "").strip().lower()
    if normalized not in PROVIDER_PRESETS:
        supported = ", ".join(sorted(PROVIDER_PRESETS))
        raise ValueError(f"Unsupported provider: {provider}. Supported providers: {supported}")
    return normalized


def _normalize_targets(targets: Iterable[str] | None) -> list[str]:
    requested = list(targets or ["hermes", "jros"])
    normalized: list[str] = []
    for target in requested:
        value = str(target or "").strip().lower()
        if value not in {"hermes", "jros"}:
            raise ValueError(f"Unsupported sync target: {target}. Supported targets: hermes, jros")
        if value not in normalized:
            normalized.append(value)
    if not normalized:
        raise ValueError("At least one sync target is required")
    return normalized


def _resolved_provider_values(provider: str, base_url: str | None, api_key_env: str | None) -> tuple[str | None, str | None]:
    preset = PROVIDER_PRESETS[provider]
    resolved_base_url = str(base_url).strip() if base_url else preset.get("base_url")
    resolved_api_key_env = str(api_key_env).strip() if api_key_env else preset.get("api_key_env")
    return resolved_base_url or None, resolved_api_key_env or None


def _sync_hermes_config(config: dict[str, Any], provider: str, model: str, base_url: str | None) -> dict[str, Any]:
    updated = deepcopy(config)
    model_config = updated.get("model")
    if not isinstance(model_config, dict):
        model_config = {}
        updated["model"] = model_config
    model_config["provider"] = provider
    model_config["default"] = model
    if base_url:
        model_config["base_url"] = base_url
    else:
        model_config.pop("base_url", None)

    # Hermes' ``ollama launch`` command registers a named provider rather than
    # using the built-in ``ollama`` slug.  Keep that provider self-contained so
    # a fresh ARES install (or a model picked from the ARES UI) can be reopened
    # by the standalone ``hermes`` command with the exact same local model.
    if provider == "ollama-launch":
        providers = updated.get("providers")
        if not isinstance(providers, dict):
            providers = {}
            updated["providers"] = providers
        launch = providers.get("ollama-launch")
        if not isinstance(launch, dict):
            launch = {}
            providers["ollama-launch"] = launch
        launch.setdefault("name", "Ollama")
        launch["api"] = base_url or launch.get("api") or PROVIDER_PRESETS[provider]["base_url"]
        launch["default_model"] = model
        models = launch.get("models")
        if not isinstance(models, list):
            models = []
        # Preserve Hermes' discovered list, but guarantee the selected model is
        # present so the picker survives a cold restart before Ollama refreshes.
        if model not in models:
            models.append(model)
        launch["models"] = models
    return updated


def _sync_jros_config(
    config: dict[str, Any],
    provider: str,
    model: str,
    base_url: str | None,
    api_key_env: str | None,
) -> dict[str, Any]:
    updated = deepcopy(config)
    external_model = updated.get("external_model")
    if not isinstance(external_model, dict):
        external_model = {}
        updated["external_model"] = external_model
    external_model["enabled"] = True
    external_model["provider"] = provider
    external_model["model"] = model
    if base_url:
        external_model["base_url"] = base_url
    else:
        external_model.pop("base_url", None)
    if api_key_env:
        external_model["api_key_env"] = api_key_env
    else:
        external_model.pop("api_key_env", None)
    return updated


def _path_result(path: Path, changed: bool) -> dict[str, Any]:
    return {"path": str(path), "changed": changed}


def _jros_supported_fallback_chain(
    fallback_chain: list[Any],
    jros_current: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    """Translate Hermes fallback entries into JROS-runnable provider entries."""
    external_model = jros_current.get("external_model") if isinstance(jros_current, dict) else None
    active_identity: tuple[str, str] | None = None
    if isinstance(external_model, dict) and external_model.get("enabled"):
        active_provider = str(external_model.get("provider") or "").strip().lower()
        active_model = str(external_model.get("model") or "").strip().lower()
        if active_provider and active_model:
            active_identity = (active_provider, active_model)

    translated: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()

    for raw_entry in fallback_chain:
        if not isinstance(raw_entry, dict):
            skipped.append({"provider": "", "model": "", "reason": "entry is not an object"})
            continue
        provider = str(raw_entry.get("provider") or "").strip().lower()
        model = str(raw_entry.get("model") or "").strip()
        if not provider or not model:
            skipped.append({"provider": provider, "model": model, "reason": "missing provider or model"})
            continue

        mapped_provider = JROS_FALLBACK_PROVIDER_MAP.get(provider)
        if not mapped_provider:
            skipped.append({
                "provider": provider,
                "model": model,
                "reason": "provider is not supported by JROS fallback runtime",
            })
            continue

        identity = (mapped_provider.lower(), model.lower())
        if active_identity is not None and identity == active_identity:
            skipped.append({"provider": provider, "model": model, "reason": "same as active JROS external_model"})
            continue
        if identity in seen:
            skipped.append({"provider": provider, "model": model, "reason": "duplicate fallback route"})
            continue

        seen.add(identity)
        entry = deepcopy(raw_entry)
        entry["provider"] = mapped_provider
        translated.append(entry)

    return translated, skipped


def sync_provider(
    provider: str,
    model: str,
    base_url: str | None = None,
    targets: Iterable[str] | None = None,
    api_key_env: str | None = None,
    hermes_config_path: str | os.PathLike[str] | None = None,
    jros_config_path: str | os.PathLike[str] | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Sync provider settings to requested config targets.

    Returns a JSON-safe dictionary. The function never writes API key values;
    callers should instruct users to set the returned env var themselves.
    """
    normalized_provider = _normalize_provider(provider)
    normalized_model = str(model or "").strip()
    if not normalized_model:
        raise ValueError("model is required")
    normalized_targets = _normalize_targets(targets)
    resolved_base_url, resolved_api_key_env = _resolved_provider_values(normalized_provider, base_url, api_key_env)

    results: dict[str, Any] = {
        "ok": True,
        "provider": normalized_provider,
        "model": normalized_model,
        "base_url": resolved_base_url,
        "api_key_env": resolved_api_key_env,
        "required_env": [resolved_api_key_env] if resolved_api_key_env else [],
        "targets": {},
        "changed_targets": [],
        "dry_run": bool(dry_run),
        "secret_values_written": False,
        "fallback_chain_synced": False,
    }

    if "hermes" in normalized_targets:
        if hermes_config_path is None:
            raise ValueError("hermes_config_path is required when syncing Hermes")
        path = expand_path(hermes_config_path)
        current = load_yaml_config(path)
        updated = _sync_hermes_config(current, normalized_provider, normalized_model, resolved_base_url)
        changed = updated != current
        if changed and not dry_run:
            save_yaml_config(path, updated)
        results["targets"]["hermes"] = _path_result(path, changed)
        if changed:
            results["changed_targets"].append("hermes")

    if "jros" in normalized_targets:
        path = expand_path(jros_config_path) if jros_config_path is not None else resolve_jros_config_path()
        current = load_yaml_config(path)
        # JROS uses its own small provider vocabulary.  Named Hermes custom
        # providers such as ``ollama-launch`` still route to JROS's canonical
        # Ollama adapter while retaining the original provider in Hermes.
        jros_provider = JROS_FALLBACK_PROVIDER_MAP.get(normalized_provider, normalized_provider)
        if not jros_provider:
            raise ValueError(f"Provider {normalized_provider} cannot be routed through JROS")
        updated = _sync_jros_config(
            current,
            jros_provider,
            normalized_model,
            resolved_base_url,
            resolved_api_key_env,
        )
        changed = updated != current
        if changed and not dry_run:
            save_yaml_config(path, updated)
        results["targets"]["jros"] = _path_result(path, changed)
        if changed:
            results["changed_targets"].append("jros")

    return results


def sync_fallback_chain(
    hermes_config_path: str | os.PathLike[str] | None = None,
    jros_config_path: str | os.PathLike[str] | None = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Sync the fallback_providers chain from Hermes config to JROS config.
    
    Returns a JSON-safe dictionary describing what was synced.
    """
    results: dict[str, Any] = {
        "ok": True,
        "fallback_chain_synced": False,
        "dry_run": bool(dry_run),
        "targets": {},
        "changed_targets": [],
        "fallback_entries_synced": 0,
    }
    
    if hermes_config_path is None:
        raise ValueError("hermes_config_path is required")
    
    hermes_path = expand_path(hermes_config_path)
    hermes_current = load_yaml_config(hermes_path)
    fallback_chain = hermes_current.get("fallback_providers", [])
    
    if not isinstance(fallback_chain, list) or not fallback_chain:
        results["targets"]["hermes"] = {"path": str(hermes_path), "changed": False, "note": "no fallback chain"}
        return results
    
    results["targets"]["hermes"] = {
        "path": str(hermes_path),
        "changed": False,
        "fallback_entries": len(fallback_chain),
    }
    
    if jros_config_path is not None or resolve_jros_config_path().exists():
        jros_path = expand_path(jros_config_path) if jros_config_path is not None else resolve_jros_config_path()
        jros_current = load_yaml_config(jros_path)
        
        updated = deepcopy(jros_current)
        jros_fallback_chain, skipped_entries = _jros_supported_fallback_chain(fallback_chain, jros_current)
        updated["fallback_providers"] = deepcopy(jros_fallback_chain)
        
        changed = updated != jros_current
        if changed and not dry_run:
            save_yaml_config(jros_path, updated)
        
        results["targets"]["jros"] = _path_result(jros_path, changed)
        results["targets"]["jros"]["skipped_entries"] = skipped_entries
        results["fallback_chain_synced"] = True
        results["fallback_entries_synced"] = len(jros_fallback_chain)
        if changed:
            results["changed_targets"].append("jros")
    
    return results
