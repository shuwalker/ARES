from pathlib import Path

from fastapi.testclient import TestClient
import pytest
import yaml

from api.ares_provider_sync import resolve_jros_config_path, sync_fallback_chain, sync_provider
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_mutation_identity
from fastapi_app.routers.onboarding import require_onboarding_mutation


def _write_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def _read_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def test_gemini_sync_updates_ares_and_jros_preserving_unrelated_keys(tmp_path):
    ares_config = tmp_path / "ares" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    _write_yaml(ares_config, {"model": {"provider": "openai", "default": "gpt-4o"}, "ui": {"theme": "dark"}})
    _write_yaml(
        jros_config,
        {
            "external_model": {"enabled": False, "provider": "openai", "model": "gpt-4o", "api_key_credential": "existing"},
            "agent": {"name": "ARES"},
        },
    )

    result = sync_provider(
        "gemini",
        "gemini-2.5-pro",
        targets=["ares", "jros"],
        ares_config_path=ares_config,
        jros_config_path=jros_config,
    )

    assert result["ok"] is True
    assert set(result["changed_targets"]) == {"ares", "jros"}
    assert result["secret_values_written"] is False
    assert result["api_key_env"] == "GOOGLE_API_KEY"
    assert result["required_env"] == ["GOOGLE_API_KEY"]

    ares = _read_yaml(ares_config)
    assert ares["model"] == {
        "provider": "gemini",
        "default": "gemini-2.5-pro",
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
    }
    assert ares["ui"] == {"theme": "dark"}

    jros = _read_yaml(jros_config)
    assert jros["external_model"]["enabled"] is True
    assert jros["external_model"]["provider"] == "gemini"
    assert jros["external_model"]["model"] == "gemini-2.5-pro"
    assert jros["external_model"]["base_url"] == "https://generativelanguage.googleapis.com/v1beta"
    assert jros["external_model"]["api_key_env"] == "GOOGLE_API_KEY"
    assert jros["external_model"]["api_key_credential"] == "existing"
    assert jros["agent"] == {"name": "ARES"}


def test_dry_run_reports_changes_without_writing(tmp_path):
    ares_config = tmp_path / "ares" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    original_ares = {"model": {"provider": "openai", "default": "gpt-4o"}}
    original_jros = {"external_model": {"enabled": False, "provider": "openai", "model": "gpt-4o"}}
    _write_yaml(ares_config, original_ares)
    _write_yaml(jros_config, original_jros)

    result = sync_provider(
        "gemini",
        "gemini-2.5-flash",
        targets=["ares", "jros"],
        ares_config_path=ares_config,
        jros_config_path=jros_config,
        dry_run=True,
    )

    assert result["ok"] is True
    assert result["dry_run"] is True
    assert set(result["changed_targets"]) == {"ares", "jros"}
    assert _read_yaml(ares_config) == original_ares
    assert _read_yaml(jros_config) == original_jros


def test_unsupported_provider_is_rejected(tmp_path):
    with pytest.raises(ValueError, match="Unsupported provider"):
        sync_provider("not-a-provider", "model", targets=["ares"], ares_config_path=tmp_path / "config.yaml")


def test_resolve_jros_config_path_prefers_explicit_env_override(tmp_path, monkeypatch):
    override = tmp_path / "custom" / "config.yaml"
    _write_yaml(override, {"external_model": {}})
    fallback_instance = tmp_path / "fallback" / "config.yaml"
    _write_yaml(fallback_instance, {"external_model": {}})

    monkeypatch.setenv("ARES_JROS_CONFIG_PATH", str(override))
    monkeypatch.setenv("JAEGER_INSTANCE_DIR", str(fallback_instance.parent))

    assert resolve_jros_config_path() == override


def test_provider_sync_route_lives_in_handle_post_not_handle_get():
    with TestClient(create_app()) as client:
        response = client.get("/api/ares/provider/sync")
    assert response.status_code == 404


def test_provider_sync_route_requires_onboarding_gate_when_auth_disabled(monkeypatch):
    app = create_app()
    identity = RequestIdentity(None, None, False)
    app.dependency_overrides[require_mutation_identity] = lambda: identity
    monkeypatch.setattr("api.network_trust.onboarding_gate_allows", lambda *args: False)
    with TestClient(app) as client:
        response = client.post(
            "/api/ares/provider/sync",
            json={"provider": "gemini", "model": "gemini-2.5-pro"},
        )
    assert response.status_code == 403
    assert "local networks" in response.json()["error"]


def test_provider_sync_post_route_calls_sync_provider(monkeypatch, tmp_path):
    body = {
        "provider": "gemini",
        "model": "gemini-2.5-pro",
        "base_url": "https://example.test/v1",
        "api_key_env": "GOOGLE_API_KEY",
        "targets": ["ares"],
        "dry_run": True,
    }
    captured = {}

    def fake_sync_provider(**kwargs):
        captured["kwargs"] = kwargs
        return {"ok": True, "changed_targets": ["ares"]}

    app = create_app()
    app.dependency_overrides[require_onboarding_mutation] = lambda: RequestIdentity(None, None, False)
    monkeypatch.setattr("api.config._get_config_path", lambda: tmp_path / "ares" / "config.yaml")
    monkeypatch.setattr("api.ares_provider_sync.sync_provider", fake_sync_provider)
    with TestClient(app) as client:
        response = client.post("/api/ares/provider/sync", json=body)
    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert captured["kwargs"] == {
        "provider": "gemini",
        "model": "gemini-2.5-pro",
        "base_url": "https://example.test/v1",
        "targets": ["ares"],
        "api_key_env": "GOOGLE_API_KEY",
        "ares_config_path": tmp_path / "ares" / "config.yaml",
        "dry_run": True,
    }


def test_fallback_chain_sync_updates_jros(tmp_path):
    """sync_fallback_chain translates Ares fallback_providers to JROS-runnable providers."""
    ares_config = tmp_path / "ares" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    _write_yaml(ares_config, {
        "model": {"provider": "ollama-cloud", "default": "deepseek-v4-flash"},
        "fallback_providers": [
            {"provider": "openai-codex", "model": "gpt-5.5"},
            {"provider": "ollama-cloud", "model": "glm-4.7"},
            {"provider": "ollama-local", "model": "gemma4:e4b-mlx"},
        ],
    })
    _write_yaml(jros_config, {"external_model": {"enabled": False}})
    
    result = sync_fallback_chain(
        ares_config_path=ares_config,
        jros_config_path=jros_config,
    )
    
    assert result["ok"] is True
    assert result["fallback_chain_synced"] is True
    assert result["fallback_entries_synced"] == 2
    assert "jros" in result["changed_targets"]
    assert result["targets"]["jros"]["skipped_entries"] == [
        {
            "provider": "openai-codex",
            "model": "gpt-5.5",
            "reason": "provider is not supported by JROS fallback runtime",
        }
    ]
    
    jros = _read_yaml(jros_config)
    assert jros["fallback_providers"] == [
        {"provider": "ollama-cloud", "model": "glm-4.7"},
        {"provider": "ollama", "model": "gemma4:e4b-mlx"},
    ]


def test_fallback_chain_sync_dry_run(tmp_path):
    """sync_fallback_chain dry_run reports changes without writing."""
    ares_config = tmp_path / "ares" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    original_jros = {"external_model": {"enabled": False}}
    _write_yaml(ares_config, {
        "fallback_providers": [{"provider": "gemini", "model": "gemini-2.5-pro"}],
    })
    _write_yaml(jros_config, original_jros)
    
    result = sync_fallback_chain(
        ares_config_path=ares_config,
        jros_config_path=jros_config,
        dry_run=True,
    )
    
    assert result["ok"] is True
    assert result["dry_run"] is True
    assert result["fallback_chain_synced"] is True
    assert _read_yaml(jros_config) == original_jros


def test_fallback_chain_sync_no_fallback_chain(tmp_path):
    """sync_fallback_chain handles missing fallback_providers gracefully."""
    ares_config = tmp_path / "ares" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    _write_yaml(ares_config, {"model": {"provider": "openai"}})
    _write_yaml(jros_config, {"external_model": {}})
    
    result = sync_fallback_chain(
        ares_config_path=ares_config,
        jros_config_path=jros_config,
    )
    
    assert result["ok"] is True
    assert result["fallback_chain_synced"] is False
    assert result["fallback_entries_synced"] == 0
    assert result["targets"]["ares"]["note"] == "no fallback chain"
