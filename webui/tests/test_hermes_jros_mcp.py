"""api.hermes_jros_mcp — mirror-direction MCP config glue (JROS -> Hermes)."""
from pathlib import Path
from types import SimpleNamespace

import pytest

from api import hermes_jros_mcp


@pytest.fixture(autouse=True)
def _fake_agent_dir(monkeypatch, tmp_path):
    monkeypatch.setattr("api.config._AGENT_DIR", tmp_path)


def test_jros_mcp_available_requires_launcher_and_agent_dir(monkeypatch, tmp_path):
    launcher = tmp_path / "jaeger"
    launcher.touch()
    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: launcher)
    assert hermes_jros_mcp.jros_mcp_available() is True

    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: tmp_path / "missing")
    assert hermes_jros_mcp.jros_mcp_available() is False


def test_sync_jros_mcp_server_merges_without_clobbering_other_servers(monkeypatch, tmp_path):
    launcher = tmp_path / "jaeger"
    launcher.touch()
    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: launcher)
    monkeypatch.setattr("api.jros_gateway_chat._jros_instance_name", lambda: "lilith")
    monkeypatch.setattr("api.jros_gateway_chat.local_jros_root", lambda: tmp_path)

    saved = {}
    existing_config = {"mcp_servers": {"other-server": {"command": "foo"}}}

    fake_hermes_config = SimpleNamespace(
        load_config=lambda: dict(existing_config),
        save_config=lambda cfg, **kw: saved.setdefault("config", cfg),
    )
    monkeypatch.setitem(__import__("sys").modules, "hermes_cli.config", fake_hermes_config)

    result = hermes_jros_mcp.sync_jros_mcp_server(enabled=True)

    assert result["ok"] is True
    assert result["enabled"] is True
    servers = saved["config"]["mcp_servers"]
    assert "other-server" in servers, "must not clobber pre-existing MCP servers"
    entry = servers["jros"]
    assert entry["command"] == str(launcher)
    assert entry["args"] == ["mcp", "lilith"]
    assert entry["cwd"] == str(tmp_path)


def test_sync_jros_mcp_server_disable_removes_entry_only(monkeypatch, tmp_path):
    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: tmp_path / "jaeger")

    saved = {}
    existing_config = {"mcp_servers": {"jros": {"command": "x"}, "other-server": {"command": "foo"}}}
    fake_hermes_config = SimpleNamespace(
        load_config=lambda: dict(existing_config),
        save_config=lambda cfg, **kw: saved.setdefault("config", cfg),
    )
    monkeypatch.setitem(__import__("sys").modules, "hermes_cli.config", fake_hermes_config)

    result = hermes_jros_mcp.sync_jros_mcp_server(enabled=False)

    assert result["enabled"] is False
    servers = saved["config"]["mcp_servers"]
    assert "jros" not in servers
    assert "other-server" in servers


def test_sync_jros_mcp_server_requires_agent_dir(monkeypatch, tmp_path):
    monkeypatch.setattr("api.config._AGENT_DIR", None)
    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: tmp_path / "jaeger")
    with pytest.raises(RuntimeError):
        hermes_jros_mcp.sync_jros_mcp_server(enabled=True)


def test_sync_jros_mcp_server_requires_launcher_when_enabling(monkeypatch, tmp_path):
    monkeypatch.setattr("api.jros_paths.jaeger_launcher", lambda: tmp_path / "missing")
    with pytest.raises(RuntimeError):
        hermes_jros_mcp.sync_jros_mcp_server(enabled=True)
