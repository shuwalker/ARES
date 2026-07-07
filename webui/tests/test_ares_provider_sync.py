from pathlib import Path
from types import SimpleNamespace

import api.routes as routes
import pytest
import yaml

from api.ares_provider_sync import resolve_jros_config_path, sync_fallback_chain, sync_provider


def _write_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def _read_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def test_gemini_sync_updates_hermes_and_jros_preserving_unrelated_keys(tmp_path):
    hermes_config = tmp_path / "hermes" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    _write_yaml(hermes_config, {"model": {"provider": "openai", "default": "gpt-4o"}, "ui": {"theme": "dark"}})
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
        targets=["hermes", "jros"],
        hermes_config_path=hermes_config,
        jros_config_path=jros_config,
    )

    assert result["ok"] is True
    assert set(result["changed_targets"]) == {"hermes", "jros"}
    assert result["secret_values_written"] is False
    assert result["api_key_env"] == "GOOGLE_API_KEY"
    assert result["required_env"] == ["GOOGLE_API_KEY"]

    hermes = _read_yaml(hermes_config)
    assert hermes["model"] == {
        "provider": "gemini",
        "default": "gemini-2.5-pro",
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
    }
    assert hermes["ui"] == {"theme": "dark"}

    jros = _read_yaml(jros_config)
    assert jros["external_model"]["enabled"] is True
    assert jros["external_model"]["provider"] == "gemini"
    assert jros["external_model"]["model"] == "gemini-2.5-pro"
    assert jros["external_model"]["base_url"] == "https://generativelanguage.googleapis.com/v1beta"
    assert jros["external_model"]["api_key_env"] == "GOOGLE_API_KEY"
    assert jros["external_model"]["api_key_credential"] == "existing"
    assert jros["agent"] == {"name": "ARES"}


def test_dry_run_reports_changes_without_writing(tmp_path):
    hermes_config = tmp_path / "hermes" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    original_hermes = {"model": {"provider": "openai", "default": "gpt-4o"}}
    original_jros = {"external_model": {"enabled": False, "provider": "openai", "model": "gpt-4o"}}
    _write_yaml(hermes_config, original_hermes)
    _write_yaml(jros_config, original_jros)

    result = sync_provider(
        "gemini",
        "gemini-2.5-flash",
        targets=["hermes", "jros"],
        hermes_config_path=hermes_config,
        jros_config_path=jros_config,
        dry_run=True,
    )

    assert result["ok"] is True
    assert result["dry_run"] is True
    assert set(result["changed_targets"]) == {"hermes", "jros"}
    assert _read_yaml(hermes_config) == original_hermes
    assert _read_yaml(jros_config) == original_jros


def test_unsupported_provider_is_rejected(tmp_path):
    with pytest.raises(ValueError, match="Unsupported provider"):
        sync_provider("not-a-provider", "model", targets=["hermes"], hermes_config_path=tmp_path / "config.yaml")


def test_resolve_jros_config_path_prefers_explicit_env_override(tmp_path, monkeypatch):
    override = tmp_path / "custom" / "config.yaml"
    _write_yaml(override, {"external_model": {}})
    fallback_instance = tmp_path / "fallback" / "config.yaml"
    _write_yaml(fallback_instance, {"external_model": {}})

    monkeypatch.setenv("ARES_JROS_CONFIG_PATH", str(override))
    monkeypatch.setenv("JAEGER_INSTANCE_DIR", str(fallback_instance.parent))

    assert resolve_jros_config_path() == override


def test_provider_sync_route_lives_in_handle_post_not_handle_get():
    source = Path(routes.__file__).read_text(encoding="utf-8")
    handle_get = source[source.index("def handle_get") : source.index("def handle_post")]
    handle_post = source[source.index("def handle_post") :]

    assert '"/api/ares/provider/sync"' not in handle_get
    assert '"/api/ares/provider/sync"' in handle_post
    assert handle_post.index('"/api/ares/backend/set"') < handle_post.index('"/api/ares/provider/sync"')


def test_provider_sync_route_requires_onboarding_gate_when_auth_disabled(monkeypatch):
    captured = {}

    def fake_bad(handler, msg, status=400):
        captured["response"] = {"data": {"error": msg}, "status": status}
        return True

    monkeypatch.setattr(routes, "_check_csrf", lambda handler: True)
    monkeypatch.setattr(routes, "read_body", lambda handler: {"provider": "gemini", "model": "gemini-2.5-pro"})
    monkeypatch.setattr(routes, "_onboarding_gate_allows", lambda handler, auth_enabled=None: False)
    monkeypatch.setattr(routes, "bad", fake_bad)

    assert routes.handle_post(object(), SimpleNamespace(path="/api/ares/provider/sync")) is True
    assert captured["response"]["status"] == 403
    assert "local networks" in captured["response"]["data"]["error"]


def test_provider_sync_post_route_calls_sync_provider(monkeypatch, tmp_path):
    body = {
        "provider": "gemini",
        "model": "gemini-2.5-pro",
        "base_url": "https://example.test/v1",
        "api_key_env": "GOOGLE_API_KEY",
        "targets": ["hermes"],
        "dry_run": True,
    }
    captured = {}

    def fake_sync_provider(**kwargs):
        captured["kwargs"] = kwargs
        return {"ok": True, "changed_targets": ["hermes"]}

    def fake_j(handler, data, status=200, headers=None):
        captured["response"] = {"data": data, "status": status}
        return True

    monkeypatch.setattr(routes, "_check_csrf", lambda handler: True)
    monkeypatch.setattr(routes, "_onboarding_gate_allows", lambda handler, auth_enabled=None: True)
    monkeypatch.setattr(routes, "read_body", lambda handler: body)
    monkeypatch.setattr(routes, "_active_profile_config_path", lambda: tmp_path / "hermes" / "config.yaml")
    monkeypatch.setattr("api.ares_provider_sync.sync_provider", fake_sync_provider)
    monkeypatch.setattr(routes, "j", fake_j)

    assert routes.handle_post(object(), SimpleNamespace(path="/api/ares/provider/sync")) is True
    assert captured["response"] == {"data": {"ok": True, "changed_targets": ["hermes"]}, "status": 200}
    assert captured["kwargs"] == {
        "provider": "gemini",
        "model": "gemini-2.5-pro",
        "base_url": "https://example.test/v1",
        "targets": ["hermes"],
        "api_key_env": "GOOGLE_API_KEY",
        "hermes_config_path": tmp_path / "hermes" / "config.yaml",
        "dry_run": True,
    }


def test_fallback_chain_sync_updates_jros(tmp_path):
    """sync_fallback_chain translates Hermes fallback_providers to JROS-runnable providers."""
    hermes_config = tmp_path / "hermes" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    _write_yaml(hermes_config, {
        "model": {"provider": "ollama-cloud", "default": "deepseek-v4-flash"},
        "fallback_providers": [
            {"provider": "openai-codex", "model": "gpt-5.5"},
            {"provider": "ollama-cloud", "model": "glm-4.7"},
            {"provider": "ollama-local", "model": "gemma4:e4b-mlx"},
        ],
    })
    _write_yaml(jros_config, {"external_model": {"enabled": False}})
    
    result = sync_fallback_chain(
        hermes_config_path=hermes_config,
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
    hermes_config = tmp_path / "hermes" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    original_jros = {"external_model": {"enabled": False}}
    _write_yaml(hermes_config, {
        "fallback_providers": [{"provider": "gemini", "model": "gemini-2.5-pro"}],
    })
    _write_yaml(jros_config, original_jros)
    
    result = sync_fallback_chain(
        hermes_config_path=hermes_config,
        jros_config_path=jros_config,
        dry_run=True,
    )
    
    assert result["ok"] is True
    assert result["dry_run"] is True
    assert result["fallback_chain_synced"] is True
    assert _read_yaml(jros_config) == original_jros


def test_fallback_chain_sync_no_fallback_chain(tmp_path):
    """sync_fallback_chain handles missing fallback_providers gracefully."""
    hermes_config = tmp_path / "hermes" / "config.yaml"
    jros_config = tmp_path / "jros" / "config.yaml"
    
    _write_yaml(hermes_config, {"model": {"provider": "openai"}})
    _write_yaml(jros_config, {"external_model": {}})
    
    result = sync_fallback_chain(
        hermes_config_path=hermes_config,
        jros_config_path=jros_config,
    )
    
    assert result["ok"] is True
    assert result["fallback_chain_synced"] is False
    assert result["fallback_entries_synced"] == 0
    assert result["targets"]["hermes"]["note"] == "no fallback chain"
