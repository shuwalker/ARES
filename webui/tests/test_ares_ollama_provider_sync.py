"""Regression coverage for the shared Ollama provider lane."""

from pathlib import Path

from api.ares_provider_sync import (
    JROS_FALLBACK_PROVIDER_MAP,
    PROVIDER_PRESETS,
    load_yaml_config,
    sync_provider,
)
from api.jros_gateway_chat import _requested_jros_model
from api.routes import _JROS_COMPATIBLE_MODEL_PROVIDERS


def test_ollama_launch_is_a_local_provider_alias():
    assert PROVIDER_PRESETS["ollama-launch"]["base_url"].endswith("/v1")
    assert JROS_FALLBACK_PROVIDER_MAP["ollama-launch"] == "ollama"
    assert "ollama-launch" in _JROS_COMPATIBLE_MODEL_PROVIDERS
    assert _requested_jros_model("@ollama-launch:gemma4", None) == (
        "ollama-launch",
        "gemma4",
    )


def test_sync_ollama_launch_persists_for_both_runtimes(tmp_path: Path):
    hermes = tmp_path / "config.yaml"
    jros = tmp_path / "jros.yaml"
    hermes.write_text("model:\n  default: old\n", encoding="utf-8")
    result = sync_provider(
        "ollama-launch",
        "gemma4",
        targets=["hermes", "jros"],
        hermes_config_path=hermes,
        jros_config_path=jros,
    )
    assert result["ok"] is True
    hermes_cfg = load_yaml_config(hermes)
    assert hermes_cfg["model"]["provider"] == "ollama-launch"
    assert hermes_cfg["model"]["default"] == "gemma4"
    assert hermes_cfg["providers"]["ollama-launch"]["default_model"] == "gemma4"
    assert "gemma4" in hermes_cfg["providers"]["ollama-launch"]["models"]
    jros_cfg = load_yaml_config(jros)
    assert jros_cfg["external_model"]["enabled"] is True
    assert jros_cfg["external_model"]["provider"] == "ollama"
    assert jros_cfg["external_model"]["model"] == "gemma4"
    assert jros_cfg["external_model"]["base_url"].endswith("/v1")
