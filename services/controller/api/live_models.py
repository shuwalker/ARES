"""Bounded, profile-scoped live model discovery cache."""

from __future__ import annotations

import copy
import threading
import time


LIVE_MODELS_CACHE_TTL = 60.0
_CACHE: dict[tuple[str, str], tuple[float, dict]] = {}
_LOCK = threading.RLock()


def clear_live_models_cache() -> None:
    with _LOCK:
        _CACHE.clear()


def _profile(value: str | None) -> str:
    if value:
        return value
    try:
        from api.profiles import get_active_profile_name

        return get_active_profile_name() or "default"
    except Exception:
        return "default"


def _label(model_id: str) -> str:
    display = model_id.rsplit("/", 1)[-1]
    return " ".join(part.upper() if part.lower() == "gpt" else part.capitalize() for part in display.split("-"))


def get_live_models(provider: str = "", *, profile: str | None = None) -> dict:
    from api.config import (
        _MODEL_PICKER_OVERFLOW_THRESHOLD,
        _MODEL_PICKER_VISIBLE_TARGET,
        _PROVIDER_MODELS,
        _is_openai_family_provider,
        _model_supports_fast_tier_for_provider,
        _resolve_provider_alias,
        get_available_models,
        get_config,
    )

    cfg = get_config()
    model_cfg = cfg.get("model") or {} if isinstance(cfg, dict) else {}
    provider_id = _resolve_provider_alias(str(provider or model_cfg.get("provider") or "").strip().lower())
    if not provider_id:
        return {"error": "no_provider", "models": []}
    key = (_profile(profile), provider_id)
    now = time.monotonic()
    with _LOCK:
        cached = _CACHE.get(key)
        if cached and now - cached[0] < LIVE_MODELS_CACHE_TTL:
            return copy.deepcopy(cached[1])
        if cached:
            _CACHE.pop(key, None)
    identifiers = []
    labels: dict[str, str] = {}
    try:
        catalog = get_available_models(force_refresh=True)
        for group in catalog.get("groups") or []:
            group_id = _resolve_provider_alias(
                str(group.get("provider_id") or group.get("provider") or "").strip().lower()
            )
            if group_id != provider_id:
                continue
            for entry in group.get("models") or []:
                model_id = str((entry or {}).get("id") or "").strip()
                if model_id:
                    identifiers.append(model_id)
                    labels[model_id] = str((entry or {}).get("label") or "").strip()
            break
    except Exception:
        identifiers = []
    if not identifiers:
        try:
            from ares_cli.models import provider_model_ids

            identifiers = list(provider_model_ids(provider_id) or [])
        except Exception:
            identifiers = []
    if not identifiers:
        identifiers = [str(item.get("id") or "") for item in _PROVIDER_MODELS.get(provider_id, [])]
    identifiers = list(dict.fromkeys(item for item in identifiers if item))
    if len(identifiers) > _MODEL_PICKER_OVERFLOW_THRESHOLD:
        identifiers = identifiers[:_MODEL_PICKER_VISIBLE_TARGET]
    annotate_fast = _is_openai_family_provider(provider_id)
    models = []
    for model_id in identifiers:
        entry = {"id": model_id, "label": labels.get(model_id) or _label(model_id)}
        if annotate_fast:
            entry["supports_fast_tier"] = _model_supports_fast_tier_for_provider(model_id, provider_id)
        models.append(entry)
    payload = {"provider": provider_id, "models": models, "count": len(models)}
    with _LOCK:
        _CACHE[key] = (time.monotonic(), copy.deepcopy(payload))
    return payload


_clear_live_models_cache = clear_live_models_cache
_LIVE_MODELS_CACHE_TTL = LIVE_MODELS_CACHE_TTL


__all__ = ["clear_live_models_cache", "get_live_models"]
