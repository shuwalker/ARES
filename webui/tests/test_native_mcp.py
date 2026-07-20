from pathlib import Path
import sys
import types

from api import native_mcp


def test_native_server_config_requires_executable(monkeypatch, tmp_path: Path):
    helper = tmp_path / "ARESNativeMCP"
    helper.write_text("#!/bin/sh\n", encoding="utf-8")
    monkeypatch.setenv("ARES_NATIVE_MCP_COMMAND", str(helper))
    assert native_mcp.native_server_config() == {}

    helper.chmod(0o755)
    config = native_mcp.native_server_config()["ares_native"]
    assert config["command"] == str(helper.resolve())
    assert config["enabled"] is True


def test_register_native_tools_is_ephemeral(monkeypatch, tmp_path: Path):
    helper = tmp_path / "ARESNativeMCP"
    helper.write_text("#!/bin/sh\n", encoding="utf-8")
    helper.chmod(0o755)
    monkeypatch.setenv("ARES_NATIVE_MCP_COMMAND", str(helper))

    captured = {}
    tools_module = types.ModuleType("tools")
    mcp_module = types.ModuleType("tools.mcp_tool")
    mcp_module.register_mcp_servers = (
        lambda servers: captured.update(servers) or ["mcp_ares_native_math_operations"]
    )
    tools_module.mcp_tool = mcp_module
    monkeypatch.setitem(sys.modules, "tools", tools_module)
    monkeypatch.setitem(sys.modules, "tools.mcp_tool", mcp_module)
    assert native_mcp.register_native_mcp_tools() == ["mcp_ares_native_math_operations"]
    assert captured["ares_native"]["command"] == str(helper.resolve())
