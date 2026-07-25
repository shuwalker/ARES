"""Regression coverage for the shared Ollama provider lane."""

from pathlib import Path

from api.ares_provider_sync import (
    JROS_FALLBACK_PROVIDER_MAP,
    PROVIDER_PRESETS,
    load_yaml_config,
    sync_provider,
    provider_runtime_status,
)
def test_ollama_launch_is_a_local_provider_alias():
    assert PROVIDER_PRESETS["ollama-launch"]["base_url"].endswith("/v1")
    assert JROS_FALLBACK_PROVIDER_MAP["ollama-launch"] == "ollama"


def test_provider_status_distinguishes_installed_from_running():
    status = provider_runtime_status("ollama-launch", "http://127.0.0.1:1/v1")
    assert status["available"] is False
    assert status["state"] in {"installed_not_running", "not_installed"}


def test_sync_ollama_launch_persists_for_both_runtimes(tmp_path: Path):
    ares = tmp_path / "config.yaml"
    jros = tmp_path / "jros.yaml"
    ares.write_text("model:\n  default: old\n", encoding="utf-8")
    result = sync_provider(
        "ollama-launch",
        "gemma4",
        targets=["ares", "jros"],
        ares_config_path=ares,
        jros_config_path=jros,
    )
    assert result["ok"] is True
    ares_cfg = load_yaml_config(ares)
    assert ares_cfg["model"]["provider"] == "ollama-launch"
    assert ares_cfg["model"]["default"] == "gemma4"
    jros_cfg = load_yaml_config(jros)
    assert jros_cfg["external_model"]["enabled"] is True
    assert jros_cfg["external_model"]["provider"] == "ollama"
    assert jros_cfg["external_model"]["model"] == "gemma4"
    assert jros_cfg["external_model"]["base_url"].endswith("/v1")
