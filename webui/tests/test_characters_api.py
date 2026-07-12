import os
import sys
import yaml
import pytest
from pathlib import Path
from types import SimpleNamespace

from api.characters import list_characters, get_character, _character_dir
from api.routes import _sync_main_model_to_jros


def test_characters_api(tmp_path, monkeypatch):
    # Create a temp directory structured like the JROS personality characters directory
    char_dir = tmp_path / "characters"
    char_dir.mkdir()

    # Write character 1 (valid character/v1 schema)
    c1_dir = char_dir / "assistant_char"
    c1_dir.mkdir()
    c1_yaml = c1_dir / "character.yaml"
    c1_data = {
        "schema": "character/v1",
        "id": "assistant_char",
        "name": "Assistant Character",
        "description": "Test description",
        "level": 3,
        "revision": 2.0,
        "identity": {
            "role": "Assistant",
            "voice_tone": "Neutral",
        },
        "prompt": {
            "custom_instructions": "Be helpful.",
            "backstory": "Test backstory.",
            "speech_patterns": ["Pattern 1"],
        },
        "traits": {
            "hexaco": {"Honesty": 4},
            "special": {"IQ": 130},
            "expression": {"Happy": True},
            "domains": ["General"],
        },
        "lore": {
            "quotes": ["Hello"],
            "mannerisms": ["Nodding"],
            "ideals": ["Helpfulness"],
            "behaviors": ["Polite"],
        },
    }
    c1_yaml.write_text(yaml.safe_dump(c1_data), encoding="utf-8")

    # Write character 2 (valid character/v1 schema, missing optional fields to test defaults)
    c2_dir = char_dir / "basic_char"
    c2_dir.mkdir()
    c2_yaml = c2_dir / "character.yaml"
    c2_data = {
        "schema": "character/v1",
        "id": "basic_char",
        "name": "Basic Character",
    }
    c2_yaml.write_text(yaml.safe_dump(c2_data), encoding="utf-8")

    # Write character 3 (invalid schema, should be skipped)
    c3_dir = char_dir / "invalid_char"
    c3_dir.mkdir()
    c3_yaml = c3_dir / "character.yaml"
    c3_yaml.write_text(yaml.safe_dump({"schema": "character/v2"}), encoding="utf-8")

    # Set up env var override
    monkeypatch.setenv("ARES_CHARACTER_DIR", str(char_dir))

    # Assert _character_dir resolves correctly
    assert _character_dir() == char_dir

    # Test list_characters
    chars = list_characters()
    assert len(chars) == 2
    char_ids = {c["id"] for c in chars}
    assert char_ids == {"assistant_char", "basic_char"}

    # Test get_character (valid)
    char1 = get_character("assistant_char")
    assert char1 is not None
    assert char1["id"] == "assistant_char"
    assert char1["name"] == "Assistant Character"
    assert char1["description"] == "Test description"
    assert char1["role"] == "Assistant"
    assert char1["voice_tone"] == "Neutral"
    assert char1["level"] == 3
    assert char1["revision"] == 2.0
    assert char1["traits"]["hexaco"] == {"Honesty": 4}
    assert char1["traits"]["special"] == {"IQ": 130}
    assert char1["traits"]["expression"] == {"Happy": True}
    assert char1["traits"]["domains"] == ["General"]
    assert char1["lore"]["quotes"] == ["Hello"]
    assert char1["lore"]["mannerisms"] == ["Nodding"]
    assert char1["lore"]["ideals"] == ["Helpfulness"]
    assert char1["lore"]["behaviors"] == ["Polite"]
    assert char1["custom_instructions"] == "Be helpful."
    assert char1["backstory"] == "Test backstory."
    assert char1["speech_patterns"] == ["Pattern 1"]

    # Test get_character (defaults checked)
    char2 = get_character("basic_char")
    assert char2 is not None
    assert char2["id"] == "basic_char"
    assert char2["name"] == "Basic Character"
    assert char2["description"] == ""
    assert char2["role"] == ""
    assert char2["voice_tone"] == ""
    assert char2["level"] == 1
    assert char2["revision"] == 1.0
    assert char2["lore"]["quotes"] == []
    assert char2["custom_instructions"] == ""

    # Test get_character (invalid schema)
    char3 = get_character("invalid_char")
    assert char3 is None

    # Test get_character (non-existent)
    char_none = get_character("nonexistent_char")
    assert char_none is None


def test_sync_main_model_to_jros_success(monkeypatch):
    called_sync = []
    called_reset = []

    def mock_sync_provider(provider, model, targets, hermes_config_path):
        called_sync.append((provider, model, targets, hermes_config_path))

    def mock_reset_jros_boot():
        called_reset.append(True)

    monkeypatch.setattr("api.ares_provider_sync.sync_provider", mock_sync_provider)
    monkeypatch.setattr("api.jros_gateway_chat.reset_jros_boot", mock_reset_jros_boot)
    monkeypatch.setattr("api.routes._active_profile_config_path", lambda: "/path/to/hermes/config.yaml")

    # Call with a model mapped in JROS_FALLBACK_PROVIDER_MAP (e.g. "openai")
    # Result contains "provider" and "model"
    _sync_main_model_to_jros({"provider": "openai", "model": "gpt-4o"})

    assert len(called_sync) == 1
    # "openai" maps to "openai" in JROS_FALLBACK_PROVIDER_MAP
    assert called_sync[0] == ("openai", "gpt-4o", ["jros"], "/path/to/hermes/config.yaml")
    assert len(called_reset) == 1


def test_sync_main_model_to_jros_no_mapping(monkeypatch):
    called_sync = []
    called_reset = []

    def mock_sync_provider(provider, model, targets, hermes_config_path):
        called_sync.append((provider, model, targets, hermes_config_path))

    def mock_reset_jros_boot():
        called_reset.append(True)

    monkeypatch.setattr("api.ares_provider_sync.sync_provider", mock_sync_provider)
    monkeypatch.setattr("api.jros_gateway_chat.reset_jros_boot", mock_reset_jros_boot)
    monkeypatch.setattr("api.routes._active_profile_config_path", lambda: "/path/to/hermes/config.yaml")

    # Call with an unmapped provider
    _sync_main_model_to_jros({"provider": "unknown-provider", "model": "some-model"})

    # Should skip sync
    assert len(called_sync) == 0
    assert len(called_reset) == 0


def test_sync_main_model_to_jros_handles_exception(monkeypatch):
    called_reset = []

    def mock_sync_provider_fail(provider, model, targets, hermes_config_path):
        raise RuntimeError("Sync failed")

    def mock_reset_jros_boot():
        called_reset.append(True)

    monkeypatch.setattr("api.ares_provider_sync.sync_provider", mock_sync_provider_fail)
    monkeypatch.setattr("api.jros_gateway_chat.reset_jros_boot", mock_reset_jros_boot)
    monkeypatch.setattr("api.routes._active_profile_config_path", lambda: "/path/to/hermes/config.yaml")

    # Should not raise exception
    _sync_main_model_to_jros({"provider": "openai", "model": "gpt-4o"})
    # Should not call reset_jros_boot if sync failed
    assert len(called_reset) == 0


def test_characters_list_api_endpoint_handles_missing_jros_dir():
    import json
    import urllib.error
    import urllib.request
    from tests._pytest_port import BASE

    url = f"{BASE}/api/ares/characters"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            assert False, "Endpoint should have failed when JROS repo dir is not set"
    except urllib.error.HTTPError as e:
        assert e.code == 400
        data = json.loads(e.read().decode("utf-8"))
        assert "Failed to list characters" in data["error"]
        assert "ARES_JROS_DIR is not set" in data["error"]


def test_character_detail_api_endpoint_handles_missing_jros_dir():
    import json
    import urllib.error
    import urllib.request
    from tests._pytest_port import BASE

    url = f"{BASE}/api/ares/character?id=test-character"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            assert False, "Endpoint should have failed when JROS repo dir is not set"
    except urllib.error.HTTPError as e:
        assert e.code == 400
        data = json.loads(e.read().decode("utf-8"))
        assert "Failed to load character" in data["error"]
        assert "ARES_JROS_DIR is not set" in data["error"]

