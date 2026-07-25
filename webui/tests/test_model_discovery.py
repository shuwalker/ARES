"""Model/provider discovery for the JROS adapter."""

from __future__ import annotations

from api.backends.model_discovery import (
    discover_jros_models,
    list_jaeger_installed_gguf,
    list_ollama_local_models,
)


def test_discover_jros_models_from_health_and_disk():
    health = {
        "ok": True,
        "model": "gemma-4-E4B-it-Q4_K_M.gguf",
        "provider": "local",
        "instance": "jarvis",
        "booted": True,
    }
    discovered = discover_jros_models(instance="jarvis", gateway_health=health)
    models = discovered.get("models") or []
    assert any(m.get("id") == "gemma-4-E4B-it-Q4_K_M.gguf" for m in models)
    assert any(m.get("in_use") for m in models)
    for m in models:
        assert not str(m.get("id") or "").startswith("(")


def test_list_helpers_do_not_raise():
    assert isinstance(list_ollama_local_models(), list)
    assert isinstance(list_jaeger_installed_gguf(), list)
