"""Safe MCP server configuration inventory and mutations."""

from __future__ import annotations

from typing import Any


MASKED_PLACEHOLDER = "••••••"


class McpConfigError(RuntimeError):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def mask_secrets(value):
    if not isinstance(value, dict):
        return value
    sensitive = ("auth", "token", "key", "secret", "password", "credential")
    return {
        key: (
            MASKED_PLACEHOLDER
            if isinstance(item, str) and any(word in key.lower() for word in sensitive)
            else mask_secrets(item) if isinstance(item, dict) else item
        )
        for key, item in value.items()
    }


def parse_enabled(value) -> bool:
    if value is None:
        return True
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "on"}:
            return True
        if normalized in {"false", "0", "no", "off"}:
            return False
    return True


def runtime_status_by_name() -> dict[str, dict]:
    try:
        from tools.mcp_tool import get_mcp_status

        statuses = get_mcp_status()
    except Exception:
        return {}
    if not isinstance(statuses, list):
        return {}
    return {
        str(item["name"]): item
        for item in statuses
        if isinstance(item, dict) and item.get("name")
    }


def server_summary(name: str, config, runtime_status=None) -> dict[str, Any]:
    runtime = runtime_status if isinstance(runtime_status, dict) else {}
    result: dict[str, Any] = {"name": name}
    if not isinstance(config, dict):
        return {
            **result,
            "transport": "invalid",
            "timeout": 120,
            "connect_timeout": 60,
            "enabled": False,
            "active": False,
            "status": "invalid_config",
            "tool_count": None,
        }
    enabled = parse_enabled(config.get("enabled", True))
    connected = bool(runtime.get("connected")) if enabled else False
    if "url" in config:
        result.update(transport="http", url=config["url"])
        if "headers" in config:
            result["headers"] = mask_secrets(config["headers"])
    elif "command" in config:
        result.update(
            transport="stdio",
            command=config.get("command", ""),
            args=config.get("args", []),
        )
        if "env" in config:
            result["env"] = mask_secrets(config["env"])
    else:
        result["transport"] = "invalid"
        enabled = connected = False
    result.update(
        timeout=config.get("timeout", 120),
        connect_timeout=config.get("connect_timeout", 60),
        enabled=enabled,
        active=connected,
        status=(
            "invalid_config"
            if result["transport"] == "invalid"
            else "disabled"
            if not enabled
            else "active"
            if connected
            else "configured"
        ),
        tool_count=runtime.get("tools") if runtime else None,
    )
    return result


def _servers() -> tuple[dict, dict]:
    from api.config import get_config

    config = get_config()
    servers = config.get("mcp_servers", {})
    return config, servers if isinstance(servers, dict) else {}


def _save(config: dict, servers: dict) -> None:
    from api.config import _get_config_path, _save_yaml_config_file, reload_config

    config["mcp_servers"] = servers
    _save_yaml_config_file(_get_config_path(), config)
    reload_config()


def list_servers() -> dict[str, Any]:
    _config, servers = _servers()
    runtime = runtime_status_by_name()
    return {
        "servers": [
            server_summary(str(name), value, runtime.get(str(name)))
            for name, value in servers.items()
        ],
        "toggle_supported": True,
        "reload_required": True,
    }


def strip_masked_values(submitted, existing):
    if not isinstance(submitted, dict) or not isinstance(existing, dict):
        return submitted
    cleaned = {}
    for key, value in submitted.items():
        if value == MASKED_PLACEHOLDER and isinstance(existing.get(key), str):
            cleaned[key] = existing[key]
        elif isinstance(value, dict) and isinstance(existing.get(key), dict):
            cleaned[key] = strip_masked_values(value, existing[key])
        else:
            cleaned[key] = value
    return cleaned


def update_server(name: str, payload: dict[str, Any]) -> dict[str, Any]:
    config, servers = _servers()
    existing = servers.get(name, {}) if isinstance(servers.get(name), dict) else {}
    server: dict[str, Any] = {}
    if payload.get("url"):
        server["url"] = str(payload["url"]).strip()
        if payload.get("headers"):
            server["headers"] = strip_masked_values(payload["headers"], existing.get("headers", {}))
    elif payload.get("command"):
        server["command"] = str(payload["command"]).strip()
        if payload.get("args"):
            server["args"] = payload["args"] if isinstance(payload["args"], list) else [payload["args"]]
        if payload.get("env"):
            server["env"] = strip_masked_values(payload["env"], existing.get("env", {}))
    else:
        raise McpConfigError("url or command is required")
    for key in ("timeout", "connect_timeout"):
        if payload.get(key) is not None:
            try:
                server[key] = int(payload[key])
            except (TypeError, ValueError):
                pass
    if "enabled" in payload:
        server["enabled"] = bool(payload["enabled"])
    servers[name] = server
    _save(config, servers)
    return {"ok": True, "server": server_summary(name, server)}


def toggle_server(name: str, enabled: bool) -> dict[str, Any]:
    config, servers = _servers()
    if name not in servers:
        raise McpConfigError(f"MCP server '{name}' not found", 404)
    if not isinstance(servers[name], dict):
        raise McpConfigError(f"MCP server '{name}' has invalid config")
    servers[name]["enabled"] = enabled
    _save(config, servers)
    return {"ok": True, "name": name, "enabled": enabled}


def delete_server(name: str) -> dict[str, Any]:
    config, servers = _servers()
    if name not in servers:
        raise McpConfigError(f"MCP server '{name}' not found", 404)
    del servers[name]
    _save(config, servers)
    return {"ok": True, "deleted": name}


_mask_secrets = mask_secrets
_parse_mcp_enabled = parse_enabled
_server_summary = server_summary
_strip_masked_values = strip_masked_values

