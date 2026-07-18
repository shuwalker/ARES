"""ARES model-catalog presentation and cross-runtime selection synchronization."""

from __future__ import annotations

import copy
import logging
from pathlib import Path


logger = logging.getLogger(__name__)
JROS_COMPATIBLE_MODEL_PROVIDERS = frozenset(
    {"ollama-cloud", "ollama-local", "ollama", "local"}
)


def active_profile_config_path() -> Path:
    try:
        from api.profiles import get_active_ares_home

        return Path(get_active_ares_home()) / "config.yaml"
    except Exception:
        from api.config import _get_config_path

        return _get_config_path()


def sync_main_model_to_jros(result: dict) -> None:
    provider = str((result or {}).get("provider") or "").strip().lower()
    model = str((result or {}).get("model") or "").strip()
    if not provider or not model:
        return
    try:
        from api.ares_provider_sync import JROS_FALLBACK_PROVIDER_MAP, sync_provider

        mapped = JROS_FALLBACK_PROVIDER_MAP.get(provider)
        if not mapped:
            return
        sync_provider(
            provider=mapped,
            model=model,
            targets=["jros"],
            ares_config_path=active_profile_config_path(),
        )
        from api.jros_gateway_chat import reset_jros_boot

        reset_jros_boot()
    except Exception:
        logger.warning("Failed to synchronize the main model with JROS", exc_info=True)


def filter_catalog_for_active_backend(catalog: dict) -> dict:
    try:
        from api.backend_selector import BACKEND_JROS, get_active_backend
        from api.config import get_config

        if get_active_backend(get_config()) != BACKEND_JROS:
            return catalog
    except Exception:
        return catalog

    filtered = copy.deepcopy(catalog or {})
    groups = [
        group
        for group in filtered.get("groups") or []
        if str(group.get("provider_id") or group.get("provider") or "").strip().lower()
        in JROS_COMPATIBLE_MODEL_PROVIDERS
    ]
    filtered["groups"] = groups
    filtered["ares_backend"] = "jros"
    filtered["compatible_providers"] = sorted(JROS_COMPATIBLE_MODEL_PROVIDERS)
    badges = filtered.get("configured_model_badges")
    if isinstance(badges, dict):
        filtered["configured_model_badges"] = {
            model_id: badge
            for model_id, badge in badges.items()
            if str((badge or {}).get("provider") or "").strip().lower()
            in JROS_COMPATIBLE_MODEL_PROVIDERS
        }
    active_provider = str(filtered.get("active_provider") or "").strip().lower()
    if active_provider not in JROS_COMPATIBLE_MODEL_PROVIDERS:
        first = groups[0] if groups else {}
        filtered["active_provider"] = first.get("provider_id") or first.get("provider") or None
    default_model = str(filtered.get("default_model") or "").strip()
    default_present = any(
        (model or {}).get("id") == default_model
        for group in groups
        for key in ("models", "extra_models")
        for model in (group.get(key) or [])
    )
    if not default_present:
        filtered["default_model"] = next(
            (
                (models[0] or {}).get("id")
                for group in groups
                if (models := (group.get("models") or group.get("extra_models") or []))
            ),
            None,
        )
    return filtered


_sync_main_model_to_jros = sync_main_model_to_jros
_filter_model_catalog_for_active_ares_backend = filter_catalog_for_active_backend

