from __future__ import annotations


def _catalog():
    return {
        "active_provider": "xai-oauth",
        "default_model": "grok-4.3",
        "configured_model_badges": {
            "grok-4.3": {"provider": "xai-oauth"},
            "glm-5.1": {"provider": "ollama-cloud"},
            "gemma4:e4b-mlx": {"provider": "ollama-local"},
            "gpt-5.5": {"provider": "openai-codex"},
        },
        "groups": [
            {"provider": "XAI", "provider_id": "xai-oauth", "models": [{"id": "grok-4.3", "label": "Grok"}]},
            {"provider": "Ollama Cloud", "provider_id": "ollama-cloud", "models": [{"id": "glm-5.1", "label": "GLM"}]},
            {"provider": "Ollama Local", "provider_id": "ollama-local", "models": [{"id": "gemma4:e4b-mlx", "label": "Gemma"}]},
            {"provider": "Codex", "provider_id": "openai-codex", "models": [{"id": "gpt-5.5", "label": "GPT"}]},
        ],
    }


def test_hermes_backend_keeps_full_model_catalog(monkeypatch):
    from api import routes

    monkeypatch.setattr(routes, "get_config", lambda: {"ares_backend": "hermes"})

    result = routes._filter_model_catalog_for_active_ares_backend(_catalog())

    assert [g["provider_id"] for g in result["groups"]] == [
        "xai-oauth",
        "ollama-cloud",
        "ollama-local",
        "openai-codex",
    ]
    assert result["active_provider"] == "xai-oauth"
    assert result["default_model"] == "grok-4.3"


def test_jros_backend_shows_only_real_compatible_model_providers(monkeypatch):
    from api import routes

    monkeypatch.setattr(routes, "get_config", lambda: {"ares_backend": "jros"})

    result = routes._filter_model_catalog_for_active_ares_backend(_catalog())

    assert [g["provider_id"] for g in result["groups"]] == [
        "ollama-cloud",
        "ollama-local",
    ]
    assert "jros" not in [g["provider_id"] for g in result["groups"]]
    assert result["active_provider"] == "ollama-cloud"
    assert result["default_model"] == "glm-5.1"
    assert set(result["configured_model_badges"]) == {"glm-5.1", "gemma4:e4b-mlx"}
