"""Model/provider discovery for Hermes and JROS adapters."""

from __future__ import annotations

from api.backends.model_discovery import (
    detect_hermes_model_config,
    discover_hermes_models,
    discover_jros_models,
    list_jaeger_installed_gguf,
    list_ollama_local_models,
)


def test_detect_hermes_model_config_reads_default_provider():
    cfg = detect_hermes_model_config()
    # On this machine config has deepseek + ollama-cloud; tolerate empty CI hosts
    if cfg.get("model"):
        assert isinstance(cfg["model"], str)
        assert "{" not in cfg["model"]
    if cfg.get("provider"):
        assert isinstance(cfg["provider"], str)


def test_discover_hermes_models_lists_real_ids_only():
    discovered = discover_hermes_models()
    models = discovered.get("models") or []
    for m in models:
        assert m.get("id")
        assert not str(m["id"]).startswith("(")
        assert "{" not in str(m["id"])
        assert m.get("location") in {"local", "cloud", "unknown"}
    providers = discovered.get("providers") or []
    for p in providers:
        assert p.get("id")
        assert p.get("status") in {"configured", "referenced", "known"}


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
