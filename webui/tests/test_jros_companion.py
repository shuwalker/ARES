"""api.jros_companion — the "Name your Companion" onboarding step's call

into JROS's own ``create_instance``/``setup_defaults``.

These pin the subprocess contract discovered by live-testing against a real
JROS checkout: cross-importing ``jaeger_os`` into ARES's own venv fails with
``ModuleNotFoundError`` (msgspec, llama-cpp-python, ...) because JROS's
native/ML dependencies only ever get installed into JROS's *own* venv, never
ARES's. The fix run through ``<jros_root>/.venv/bin/python`` as a subprocess
instead of importing jaeger_os in-process — these tests mock
``subprocess.run`` so they never need a real JROS install.
"""
from __future__ import annotations

import json
import types

import pytest


def _fake_local_jros_root(root, monkeypatch):
    # jros_companion does `from api.jros_gateway_chat import local_jros_root`,
    # so the name lives in jros_companion's own namespace — patch it there,
    # not on the source module (sys.modules swaps don't reach an already
    #-bound `from X import Y` name).
    from api import jros_companion

    monkeypatch.setattr(jros_companion, "local_jros_root", lambda: root)


def _completed_process(stdout="", stderr="", returncode=0):
    return types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


def test_companion_available_false_without_local_jros(monkeypatch):
    from api import jros_companion

    _fake_local_jros_root(None, monkeypatch)
    assert jros_companion.companion_available() is False


def test_companion_available_true_with_local_jros(monkeypatch, tmp_path):
    from api import jros_companion

    _fake_local_jros_root(tmp_path, monkeypatch)
    assert jros_companion.companion_available() is True


def test_jros_python_prefers_jros_own_venv(tmp_path):
    from api import jros_companion

    venv_python = tmp_path / ".venv" / "bin" / "python"
    venv_python.parent.mkdir(parents=True)
    venv_python.write_text("#!/bin/sh\n")

    assert jros_companion._jros_python(tmp_path) == venv_python


def test_jros_python_falls_back_to_ares_interpreter_without_jros_venv(tmp_path):
    import sys

    from api import jros_companion

    assert jros_companion._jros_python(tmp_path) == jros_companion.Path(sys.executable)


def test_run_in_jros_venv_uses_jros_own_python(monkeypatch, tmp_path):
    """The exact bug found live: this must NOT be sys.executable (ARES's
    venv) when JROS has its own venv — that's what raised
    ModuleNotFoundError: msgspec against a real install."""
    from api import jros_companion

    _fake_local_jros_root(tmp_path, monkeypatch)
    venv_python = tmp_path / ".venv" / "bin" / "python"
    venv_python.parent.mkdir(parents=True)
    venv_python.write_text("#!/bin/sh\n")

    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        captured["cwd"] = kwargs.get("cwd")
        captured["env"] = kwargs.get("env")
        return _completed_process(stdout=json.dumps({"ok": True}))

    monkeypatch.setattr(jros_companion.subprocess, "run", fake_run)
    monkeypatch.setattr(jros_companion, "jros_instance_name", lambda: None)

    result = jros_companion._run_in_jros_venv("print('hi')")

    assert result == {"ok": True}
    assert captured["cmd"][0] == str(venv_python)
    assert captured["cwd"] == str(tmp_path)


def test_run_in_jros_venv_passes_configured_instance_name(monkeypatch, tmp_path):
    from api import jros_companion

    _fake_local_jros_root(tmp_path, monkeypatch)

    captured = {}

    def fake_run(cmd, **kwargs):
        captured["env"] = kwargs.get("env")
        return _completed_process(stdout="{}")

    monkeypatch.setattr(jros_companion.subprocess, "run", fake_run)
    monkeypatch.setattr(jros_companion, "jros_instance_name", lambda: "jros-dev")

    jros_companion._run_in_jros_venv("...")

    assert captured["env"]["ARES_JROS_INSTANCE"] == "jros-dev"


def test_run_in_jros_venv_raises_on_nonzero_exit(monkeypatch, tmp_path):
    from api import jros_companion

    _fake_local_jros_root(tmp_path, monkeypatch)
    monkeypatch.setattr(
        jros_companion.subprocess, "run",
        lambda *a, **k: _completed_process(stderr="boom", returncode=1),
    )
    monkeypatch.setattr(jros_companion, "jros_instance_name", lambda: None)

    with pytest.raises(RuntimeError, match="boom"):
        jros_companion._run_in_jros_venv("...")


def test_run_in_jros_venv_raises_without_local_jros(monkeypatch):
    from api import jros_companion

    _fake_local_jros_root(None, monkeypatch)

    with pytest.raises(RuntimeError, match="No local JaegerAI install"):
        jros_companion._run_in_jros_venv("...")


def test_companion_setup_defaults_parses_subprocess_json(monkeypatch, tmp_path):
    from api import jros_companion

    payload = {
        "host_memory_gb": 32.0,
        "default_character": "jarvis",
        "voices": [{"id": "am_michael", "label": "Michael"}],
        "permission_modes": [{"id": "confirm", "label": "Ask me before each action"}],
        "characters": [{"id": "jarvis", "name": "Jarvis", "role": "", "voice_id": "", "voice_tone": ""}],
    }
    monkeypatch.setattr(jros_companion, "_run_in_jros_venv", lambda *a, **k: payload)

    assert jros_companion.companion_setup_defaults() == payload
    assert jros_companion.list_characters() == payload["characters"]


def test_companion_exists_true(monkeypatch):
    from api import jros_companion

    monkeypatch.setattr(jros_companion, "_run_in_jros_venv", lambda *a, **k: {"exists": True})
    assert jros_companion.companion_exists() is True


def test_companion_exists_swallows_errors(monkeypatch):
    from api import jros_companion

    def raise_it(*a, **k):
        raise RuntimeError("no jros")

    monkeypatch.setattr(jros_companion, "_run_in_jros_venv", raise_it)
    assert jros_companion.companion_exists() is False


def test_create_companion_fallback_to_first_character_when_blank(monkeypatch):
    from api import jros_companion

    captured = {}

    def fake_run(script, *, stdin_payload=None):
        captured["payload"] = stdin_payload
        return {"ok": True, "name": "test-soul", "instance_dir": "/x/y/test-soul"}

    def fake_defaults():
        return {
            "characters": [
                {"id": "jarvis", "name": "Jarvis"},
                {"id": "tars", "name": "TARS"},
            ]
        }

    monkeypatch.setattr(jros_companion, "_run_in_jros_venv", fake_run)
    monkeypatch.setattr(jros_companion, "companion_setup_defaults", fake_defaults)

    # Empty character_id falls back to the first available character.
    result = jros_companion.create_companion(character_id="", display_name="Test Soul")
    assert result["ok"] is True
    assert captured["payload"]["character_id"] == "jarvis"

    # "default" also falls back.
    captured.clear()
    result = jros_companion.create_companion(character_id="default", display_name="Test Soul")
    assert captured["payload"]["character_id"] == "jarvis"


def test_create_companion_fails_when_no_characters_installed(monkeypatch):
    from api import jros_companion

    def fake_defaults():
        return {"characters": []}

    monkeypatch.setattr(jros_companion, "companion_setup_defaults", fake_defaults)

    with pytest.raises(ValueError, match="No characters are installed"):
        jros_companion.create_companion(character_id="")


def test_create_companion_success(monkeypatch):
    from api import jros_companion

    captured = {}

    def fake_run(script, *, stdin_payload=None):
        captured["payload"] = stdin_payload
        return {"ok": True, "name": "jarvis-jaeger", "instance_dir": "/x/y/jarvis-jaeger"}

    monkeypatch.setattr(jros_companion, "_run_in_jros_venv", fake_run)

    result = jros_companion.create_companion(
        character_id="jarvis", display_name="Jarvis", voice_id="am_michael",
    )

    assert result == {"ok": True, "name": "jarvis-jaeger", "instance_dir": "/x/y/jarvis-jaeger"}
    assert captured["payload"]["character_id"] == "jarvis"
    assert captured["payload"]["display_name"] == "Jarvis"
    assert captured["payload"]["voice_id"] == "am_michael"
    assert captured["payload"]["permission_mode"] == "confirm"
    assert captured["payload"]["make_default"] is True


def test_create_companion_raises_friendly_error_when_name_taken(monkeypatch):
    from api import jros_companion

    monkeypatch.setattr(
        jros_companion, "_run_in_jros_venv",
        lambda *a, **k: {"ok": False, "error": "exists", "message": "instance exists"},
    )

    with pytest.raises(ValueError, match="already exists"):
        jros_companion.create_companion(character_id="jarvis", name="jarvis-jaeger")


def test_create_companion_raises_on_unknown_character(monkeypatch):
    from api import jros_companion

    monkeypatch.setattr(
        jros_companion, "_run_in_jros_venv",
        lambda *a, **k: {"ok": False, "error": "unknown_character", "message": "unknown character: 'nope'"},
    )

    with pytest.raises(ValueError, match="unknown character"):
        jros_companion.create_companion(character_id="nope")
